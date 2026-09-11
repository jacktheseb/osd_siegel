#Requires -Version 5.1

<#
.SYNOPSIS
    OSDCloud OS Deployment Selector with Modern UI

.DESCRIPTION
    WPF interface for selecting the Windows version and language to deploy
    via OSDCloud Zero-Touch Installation. Runs inside WinPE.
#>

#region STA Check

if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Write-Warning "This script should be started in STA mode."
    Write-Warning "Restarting script with PowerShell STA mode..."

    Start-Process powershell.exe -ArgumentList @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-STA'
        '-File', "`"$PSCommandPath`""
    )

    exit
}

#endregion STA Check

#region Load Required Assemblies

try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Add-Type -AssemblyName PresentationCore -ErrorAction Stop
    Add-Type -AssemblyName WindowsBase -ErrorAction Stop
}
catch {
    Write-Error "Failed to load required WPF assemblies. Error: $($_.Exception.Message)"
    exit 1
}

#endregion Load Required Assemblies

#region OS Configuration Data
# Maintain the deployable OS versions and languages here. Every version is
# combined with every language, so adding an entry to either array is enough
# to make it selectable in the GUI - no XAML changes required.

$OSVersionName = "Windows 11"
$OSEdition     = "Pro"
$OSLicense     = "Retail"

$OSVersions = @(
    [PSCustomObject]@{ Build = "26H2"; Note = "Aktuellstes Feature-Update" }
    [PSCustomObject]@{ Build = "25H2"; Note = "Vorgaenger-Release" }
)

$OSLanguages = @(
    [PSCustomObject]@{ Tag = "en-us"; Label = "English" }
    [PSCustomObject]@{ Tag = "de-de"; Label = "Deutsch" }
)

#endregion OS Configuration Data

#region Hardware Summary
# Uses only CIM/WMI + WinPE environment variables so the info panel can be
# populated immediately, before the OSDCloud module is installed/imported.

function Get-HardwareSummary {
    $summary = [ordered]@{
        Manufacturer = "Unbekannt"
        Model        = "Unbekannt"
        SerialNumber = "Unbekannt"
        Firmware     = "Unbekannt"
    }

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($cs.Manufacturer) { $summary.Manufacturer = $cs.Manufacturer.Trim() }
        if ($cs.Model) { $summary.Model = $cs.Model.Trim() }
    }
    catch {
        Write-Warning "Could not read Win32_ComputerSystem: $($_.Exception.Message)"
    }

    try {
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        if ($bios.SerialNumber) { $summary.SerialNumber = $bios.SerialNumber.Trim() }
    }
    catch {
        Write-Warning "Could not read Win32_BIOS: $($_.Exception.Message)"
    }

    if ($env:firmware_type) { $summary.Firmware = $env:firmware_type }

    return [PSCustomObject]$summary
}

#endregion Hardware Summary

#region Helper Functions

function Start-OSDeployment {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    try {
        #=======================================================================
        #   [PreOS] Update and Import Modules
        #=======================================================================
        Write-Host -ForegroundColor Green "Updating OSD PowerShell Module"
        try {
            Install-Module OSDCloud -Force -SkipPublisherCheck -ErrorAction Stop
        }
        catch {
            Write-Host -ForegroundColor Yellow "OSD Module installation failed, attempting to use existing installation..."
        }

        Write-Host -ForegroundColor Green "Importing OSD PowerShell Module"
        Import-Module OSDCloud -Force -ErrorAction Stop

        # Check for Virtual Machine and set display resolution
        if ((Get-MyComputerModel) -match 'Virtual') {
            Write-Host -ForegroundColor Green "Setting Display Resolution to 1600x"
            Set-DisRes 1600
        }

        #=======================================================================
        #   [OSDCloud] Global Variables and Parameters
        #=======================================================================
        Write-Host -ForegroundColor Cyan "Configuring deployment parameters for: $($Config.DisplayName)"

        $Params = @{
            OSVersion  = $Config.OSVersion
            OSBuild    = $Config.OSBuild
            OSEdition  = $Config.OSEdition
            OSLanguage = $Config.OSLanguage
            OSLicense  = $Config.OSLicense
            ZTI        = $true
            Firmware   = $true
        }

        $Product = (Get-MyComputerProduct)
        $Model   = Get-MyComputerModel

        $Global:MyOSDCloud = [ordered]@{
            Restart                = [bool]$false
            RecoveryPartition      = [bool]$true
            OEMActivation          = [bool]$true
            WindowsUpdate          = [bool]$true
            WindowsUpdateDrivers   = [bool]$true
            WindowsDefenderUpdate  = [bool]$true
            SetTimeZone            = [bool]$true
            ShutdownSetupComplete  = [bool]$false
            SyncMSUpCatDriverUSB   = [bool]$true
            updateFirmware         = [bool]$true
            CheckSHA1              = [bool]$true
        }

        # Driver Pack Detection
        $DriverPack = Get-OSDCloudDriverPack -Product $Product -OSVersion $Params.OSVersion -OSReleaseID $Params.OSBuild

        if ($DriverPack) {
            Write-Host -ForegroundColor Yellow "Driver Pack Found: $($DriverPack.Name)"
            $Global:MyOSDCloud.DriverPackName = $DriverPack.Name
        }

        # Check for HP Device Support
        if (Test-HPIASupport) {
            Write-Host -ForegroundColor Yellow "Detected HP Device - Enabling HPIA, HP BIOS and HP TPM Updates"
            $Global:MyOSDCloud.HPTPMUpdate = [bool]$True
            if ($Product -ne '83B2' -and $Model -notmatch "zbook") {
                $Global:MyOSDCloud.HPIAALL = [bool]$true
            }
            $Global:MyOSDCloud.HPBIOSUpdate = [bool]$true
        }

        Write-Host -ForegroundColor Green "OSDCloud Configuration:"
        $Global:MyOSDCloud

        #=======================================================================
        #   [OS] Start OSDCloud Deployment
        #=======================================================================
        Write-Host -ForegroundColor Cyan "Starting OSDCloud Deployment"
        Write-Host -ForegroundColor Yellow "OS: $($Params.OSVersion) $($Params.OSBuild) ($($Params.OSLanguage))"

        Start-OSDCloud @Params

        #=======================================================================
        #   [PostOS] OOBEDeploy Configuration
        #=======================================================================
        Write-Host -ForegroundColor Green "Creating OSDeploy configuration"
        $OOBEDeployJson = @'
{
    "UpdateDrivers":  {
                          "IsPresent":  true
                      },
    "UpdateWindows":  {
                          "IsPresent":  true
                      }
}
'@
        if (!(Test-Path "C:\ProgramData\OSDeploy")) {
            New-Item "C:\ProgramData\OSDeploy" -ItemType Directory -Force | Out-Null
        }
        $OOBEDeployJson | Out-File -FilePath "C:\ProgramData\OSDeploy\OSDeploy.OOBEDeploy.json" -Encoding ascii -Force

        #=======================================================================
        #   Deployment Complete
        #=======================================================================
        Write-Host -ForegroundColor Green "Deployment configuration complete!"
        Write-Host -ForegroundColor Yellow "System will restart in 20 seconds..."
        Start-Sleep -Seconds 20
        wpeutil reboot
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "Failed to start OS Deployment.`n`nError:`n$($_.Exception.Message)",
            "OSDCloud - Deployment Error",
            "OK",
            "Error"
        ) | Out-Null

        Write-Error "Deployment failed: $($_.Exception.Message)"
    }
}

function New-OptionButton {
    param (
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Sub,
        [Parameter(Mandatory = $true)][string]$GroupName,
        [Parameter(Mandatory = $true)]$Tag,
        [switch]$Checked
    )

    $radioButton = New-Object System.Windows.Controls.RadioButton
    $radioButton.Style = $window.FindResource('SegmentedOptionStyle')
    $radioButton.GroupName = $GroupName
    $radioButton.Tag = $Tag

    $panel = New-Object System.Windows.Controls.StackPanel

    $titleBlock = New-Object System.Windows.Controls.TextBlock
    $titleBlock.Text = $Title
    $titleBlock.FontWeight = 'Bold'
    $titleBlock.FontSize = 14
    $titleBlock.Foreground = [System.Windows.Media.Brushes]::White
    [void]$panel.Children.Add($titleBlock)

    $subBlock = New-Object System.Windows.Controls.TextBlock
    $subBlock.Text = $Sub
    $subBlock.FontSize = 10
    $subBlock.Margin = '0,3,0,0'
    $subBlock.Foreground = New-Object System.Windows.Media.SolidColorBrush(
        [System.Windows.Media.ColorConverter]::ConvertFromString('#8FA4B8')
    )
    [void]$panel.Children.Add($subBlock)

    $radioButton.Content = $panel

    if ($Checked) { $radioButton.IsChecked = $true }

    return $radioButton
}

#endregion Helper Functions

#region XAML UI Definition

$xamlString = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="OSDCloud OS Deployment Selector"
        Height="600"
        Width="700"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Background="#0A1420"
        Topmost="True"
        WindowStyle="SingleBorderWindow">

    <Window.Resources>

        <!-- Palette -->
        <SolidColorBrush x:Key="BgPanel" Color="#101F30"/>
        <SolidColorBrush x:Key="BgPanelRaised" Color="#142A3F"/>
        <SolidColorBrush x:Key="BgTile" Color="#13263A"/>
        <SolidColorBrush x:Key="BgTileHover" Color="#183149"/>
        <SolidColorBrush x:Key="BorderColor" Color="#22394F"/>
        <SolidColorBrush x:Key="BorderSoft" Color="#1A2E42"/>
        <SolidColorBrush x:Key="Accent" Color="#3FA9FF"/>
        <SolidColorBrush x:Key="AccentText" Color="#BFE2FF"/>
        <SolidColorBrush x:Key="TextPrimary" Color="#EEF4FA"/>
        <SolidColorBrush x:Key="TextSecondary" Color="#A9BCCE"/>
        <SolidColorBrush x:Key="TextMuted" Color="#6D8298"/>
        <SolidColorBrush x:Key="Danger" Color="#FF5F74"/>
        <SolidColorBrush x:Key="WarnBg" Color="#2E2210"/>
        <SolidColorBrush x:Key="WarnBorder" Color="#4A380F"/>
        <SolidColorBrush x:Key="WarnText" Color="#E8C98A"/>

        <!-- Segmented option (used for both Version and Language rows) -->
        <Style x:Key="SegmentedOptionStyle" TargetType="RadioButton">
            <Setter Property="Padding" Value="14,11"/>
            <Setter Property="Margin" Value="0,0,10,10"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimary}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RadioButton">
                        <Border x:Name="OptBorder"
                                Background="{StaticResource BgTile}"
                                BorderBrush="{StaticResource BorderColor}"
                                BorderThickness="1.5"
                                CornerRadius="8"
                                Padding="{TemplateBinding Padding}"
                                MinWidth="150">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <ContentPresenter Grid.Column="0" VerticalAlignment="Center"/>
                                <Ellipse x:Name="Check"
                                         Grid.Column="1"
                                         Width="15" Height="15"
                                         Stroke="#3A5773"
                                         StrokeThickness="1.5"
                                         Fill="Transparent"
                                         VerticalAlignment="Center"
                                         Margin="10,0,0,0"/>
                            </Grid>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="OptBorder" Property="Background" Value="{StaticResource BgTileHover}"/>
                                <Setter TargetName="OptBorder" Property="BorderBrush" Value="#2F5573"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="OptBorder" Property="BorderBrush" Value="{StaticResource Accent}"/>
                                <Setter TargetName="OptBorder" Property="Background" Value="#173A56"/>
                                <Setter TargetName="Check" Property="Fill" Value="{StaticResource Accent}"/>
                                <Setter TargetName="Check" Property="Stroke" Value="{StaticResource Accent}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="DeployButtonStyle" TargetType="Button">
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="24,11"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Foreground" Value="#04140D"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bg" CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <Border.Background>
                                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                                    <GradientStop Color="#2FBD85" Offset="0"/>
                                    <GradientStop Color="#1F9C6D" Offset="1"/>
                                </LinearGradientBrush>
                            </Border.Background>
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bg" Property="Opacity" Value="0.9"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Bg" Property="Background" Value="{StaticResource BgPanelRaised}"/>
                                <Setter Property="Foreground" Value="{StaticResource TextMuted}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="CancelButtonStyle" TargetType="Button">
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="24,11"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Foreground" Value="{StaticResource TextSecondary}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bg"
                                Background="Transparent"
                                BorderBrush="{StaticResource BorderColor}"
                                BorderThickness="1.5"
                                CornerRadius="8"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bg" Property="BorderBrush" Value="{StaticResource Danger}"/>
                                <Setter Property="Foreground" Value="{StaticResource Danger}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

    </Window.Resources>

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="190"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- Left rail: hardware info -->
        <Border Grid.Column="0" Background="{StaticResource BgPanel}" BorderBrush="{StaticResource BorderSoft}" BorderThickness="0,0,1,0">
            <StackPanel Margin="18,24,18,18">
                <TextBlock Text="OSDCloud" FontSize="16" FontWeight="Bold" Foreground="{StaticResource TextPrimary}"/>
                <TextBlock Text="WinPE Deployment Console" FontSize="9.5" Foreground="{StaticResource TextMuted}" Margin="0,2,0,22" TextWrapping="Wrap"/>

                <TextBlock Text="ZIELHARDWARE" FontSize="10" FontWeight="SemiBold" Foreground="{StaticResource TextMuted}" Margin="0,0,0,10"/>

                <TextBlock Text="Hersteller" FontSize="10" Foreground="{StaticResource TextMuted}" Margin="0,0,0,1"/>
                <TextBlock Name="lblHwManufacturer" Text="-" FontSize="12" Foreground="{StaticResource TextSecondary}" Margin="0,0,0,10" TextWrapping="Wrap"/>

                <TextBlock Text="Modell" FontSize="10" Foreground="{StaticResource TextMuted}" Margin="0,0,0,1"/>
                <TextBlock Name="lblHwModel" Text="-" FontSize="12" Foreground="{StaticResource TextSecondary}" Margin="0,0,0,10" TextWrapping="Wrap"/>

                <TextBlock Text="Seriennummer" FontSize="10" Foreground="{StaticResource TextMuted}" Margin="0,0,0,1"/>
                <TextBlock Name="lblHwSerial" Text="-" FontSize="12" Foreground="{StaticResource TextSecondary}" Margin="0,0,0,10" TextWrapping="Wrap"/>

                <TextBlock Text="Firmware" FontSize="10" Foreground="{StaticResource TextMuted}" Margin="0,0,0,1"/>
                <TextBlock Name="lblHwFirmware" Text="-" FontSize="12" Foreground="{StaticResource TextSecondary}"/>

                <TextBlock Text="Treiberpaket und HPIA-Erkennung erfolgen beim Start des Deployments."
                           FontSize="9" Foreground="{StaticResource TextMuted}" TextWrapping="Wrap" Margin="0,26,0,0"/>
            </StackPanel>
        </Border>

        <!-- Main content: version / language pickers -->
        <StackPanel Grid.Column="1" Margin="28,22,28,18">

            <TextBlock Text="Welches System soll installiert werden?" FontSize="19" FontWeight="Bold" Foreground="{StaticResource TextPrimary}" TextWrapping="Wrap"/>
            <TextBlock Text="Version und Sprache waehlen - die Konfiguration wird automatisch zusammengesetzt." FontSize="11.5" Foreground="{StaticResource TextSecondary}" Margin="0,4,0,16" TextWrapping="Wrap"/>

            <TextBlock Text="WINDOWS-VERSION" FontSize="10" FontWeight="SemiBold" Foreground="{StaticResource TextMuted}" Margin="0,0,0,8"/>
            <WrapPanel Name="spVersionOptions" Margin="0,0,0,10"/>

            <TextBlock Text="SPRACHE" FontSize="10" FontWeight="SemiBold" Foreground="{StaticResource TextMuted}" Margin="0,0,0,8"/>
            <WrapPanel Name="spLanguageOptions" Margin="0,0,0,14"/>

            <Border Background="{StaticResource BgPanel}" BorderBrush="{StaticResource BorderSoft}" BorderThickness="1" CornerRadius="10" Padding="16">
                <StackPanel>
                    <TextBlock Text="ZUSAMMENGESTELLTE KONFIGURATION" FontSize="9.5" FontWeight="SemiBold" Foreground="{StaticResource TextMuted}" Margin="0,0,0,8"/>
                    <TextBlock Name="lblResultName" Text="-" FontSize="15" FontWeight="Bold" Foreground="{StaticResource TextPrimary}" Margin="0,0,0,12" TextWrapping="Wrap"/>

                    <UniformGrid Columns="2" Rows="2" Margin="0,0,0,14">
                        <Border Background="{StaticResource BgPanelRaised}" BorderBrush="{StaticResource BorderColor}" BorderThickness="1" CornerRadius="6" Padding="9,6" Margin="0,0,8,8">
                            <StackPanel>
                                <TextBlock Text="OS Version" FontSize="9" Foreground="{StaticResource TextMuted}"/>
                                <TextBlock Name="lblFieldVersion" Text="-" FontSize="12" Foreground="{StaticResource AccentText}"/>
                            </StackPanel>
                        </Border>
                        <Border Background="{StaticResource BgPanelRaised}" BorderBrush="{StaticResource BorderColor}" BorderThickness="1" CornerRadius="6" Padding="9,6" Margin="0,0,0,8">
                            <StackPanel>
                                <TextBlock Text="Build" FontSize="9" Foreground="{StaticResource TextMuted}"/>
                                <TextBlock Name="lblFieldBuild" Text="-" FontSize="12" Foreground="{StaticResource AccentText}"/>
                            </StackPanel>
                        </Border>
                        <Border Background="{StaticResource BgPanelRaised}" BorderBrush="{StaticResource BorderColor}" BorderThickness="1" CornerRadius="6" Padding="9,6" Margin="0,0,8,0">
                            <StackPanel>
                                <TextBlock Text="Edition" FontSize="9" Foreground="{StaticResource TextMuted}"/>
                                <TextBlock Name="lblFieldEdition" Text="-" FontSize="12" Foreground="{StaticResource AccentText}"/>
                            </StackPanel>
                        </Border>
                        <Border Background="{StaticResource BgPanelRaised}" BorderBrush="{StaticResource BorderColor}" BorderThickness="1" CornerRadius="6" Padding="9,6">
                            <StackPanel>
                                <TextBlock Text="Sprache" FontSize="9" Foreground="{StaticResource TextMuted}"/>
                                <TextBlock Name="lblFieldLang" Text="-" FontSize="12" Foreground="{StaticResource AccentText}"/>
                            </StackPanel>
                        </Border>
                    </UniformGrid>

                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                        <Button Name="btnCancel" Style="{StaticResource CancelButtonStyle}" Content="Abbrechen" Margin="0,0,10,0"/>
                        <Button Name="btnDeploy" Style="{StaticResource DeployButtonStyle}" Content="Deploy starten" IsEnabled="False"/>
                    </StackPanel>
                </StackPanel>
            </Border>

            <Border Background="{StaticResource WarnBg}" BorderBrush="{StaticResource WarnBorder}" BorderThickness="1" CornerRadius="8" Padding="11" Margin="0,12,0,0">
                <TextBlock Foreground="{StaticResource WarnText}" FontSize="10.5" TextWrapping="Wrap">
                    <Run FontWeight="Bold">Achtung:</Run>
                    <Run Text=" Die Installation formatiert das Zielsystem vollstaendig. Alle Daten gehen unwiderruflich verloren - vor dem Start sichern."/>
                </TextBlock>
            </Border>

        </StackPanel>
    </Grid>
</Window>
"@

#endregion XAML UI Definition

#region Load XAML

try {
    $stringReader = New-Object System.IO.StringReader($xamlString)
    $xmlReader = [System.Xml.XmlReader]::Create($stringReader)
    $window = [Windows.Markup.XamlReader]::Load($xmlReader)
}
catch {
    Write-Error "Failed to load XAML. Error: $($_.Exception.Message)"
    exit 1
}

#endregion Load XAML

#region Wire Up Controls

try {
    $lblHwManufacturer = $window.FindName('lblHwManufacturer')
    $lblHwModel        = $window.FindName('lblHwModel')
    $lblHwSerial       = $window.FindName('lblHwSerial')
    $lblHwFirmware     = $window.FindName('lblHwFirmware')

    $spVersionOptions  = $window.FindName('spVersionOptions')
    $spLanguageOptions = $window.FindName('spLanguageOptions')

    $lblResultName    = $window.FindName('lblResultName')
    $lblFieldVersion  = $window.FindName('lblFieldVersion')
    $lblFieldBuild    = $window.FindName('lblFieldBuild')
    $lblFieldEdition  = $window.FindName('lblFieldEdition')
    $lblFieldLang     = $window.FindName('lblFieldLang')

    $btnDeploy = $window.FindName('btnDeploy')
    $btnCancel = $window.FindName('btnCancel')

    if (-not $spVersionOptions -or -not $spLanguageOptions -or -not $btnDeploy -or -not $btnCancel) {
        [System.Windows.MessageBox]::Show(
            "One or more GUI controls could not be found.",
            "OSDCloud - GUI Error",
            "OK",
            "Error"
        ) | Out-Null
        exit 1
    }
}
catch {
    Write-Error "Failed to wire up controls. Error: $($_.Exception.Message)"
    exit 1
}

# Populate hardware info panel (safe pre-module-import in WinPE)
$hw = Get-HardwareSummary
$lblHwManufacturer.Text = $hw.Manufacturer
$lblHwModel.Text        = $hw.Model
$lblHwSerial.Text       = $hw.SerialNumber
$lblHwFirmware.Text     = $hw.Firmware

#endregion Wire Up Controls

#region Selection State + Result Panel

$script:SelectedVersion  = $null
$script:SelectedLanguage = $null

function Update-ResultPanel {
    if (-not $script:SelectedVersion -or -not $script:SelectedLanguage) {
        $lblResultName.Text = "Keine Auswahl"
        $lblFieldVersion.Text = "-"
        $lblFieldBuild.Text = "-"
        $lblFieldEdition.Text = "-"
        $lblFieldLang.Text = "-"
        $btnDeploy.IsEnabled = $false
        return
    }

    $v = $script:SelectedVersion
    $l = $script:SelectedLanguage

    $lblResultName.Text   = "$OSVersionName $($v.Build) $OSEdition ($($l.Label))"
    $lblFieldVersion.Text = $OSVersionName
    $lblFieldBuild.Text   = $v.Build
    $lblFieldEdition.Text = $OSEdition
    $lblFieldLang.Text    = "$($l.Tag) . $($l.Label)"
    $btnDeploy.IsEnabled  = $true
}

# Build the Version options from $OSVersions
for ($i = 0; $i -lt $OSVersions.Count; $i++) {
    $item = $OSVersions[$i]
    $isFirst = ($i -eq 0)

    $rb = New-OptionButton -Title "$OSVersionName $($item.Build)" -Sub $item.Note -GroupName 'VersionGroup' -Tag $item -Checked:$isFirst
    $rb.Add_Checked({
        param($sender, $e)
        $script:SelectedVersion = $sender.Tag
        Update-ResultPanel
    })
    [void]$spVersionOptions.Children.Add($rb)

    if ($isFirst) { $script:SelectedVersion = $item }
}

# Build the Language options from $OSLanguages
for ($i = 0; $i -lt $OSLanguages.Count; $i++) {
    $item = $OSLanguages[$i]
    $isFirst = ($i -eq 0)

    $rb = New-OptionButton -Title $item.Label -Sub $item.Tag -GroupName 'LanguageGroup' -Tag $item -Checked:$isFirst
    $rb.Add_Checked({
        param($sender, $e)
        $script:SelectedLanguage = $sender.Tag
        Update-ResultPanel
    })
    [void]$spLanguageOptions.Children.Add($rb)

    if ($isFirst) { $script:SelectedLanguage = $item }
}

Update-ResultPanel

#endregion Selection State + Result Panel

#region Event Handlers

# Deploy Button Click
$btnDeploy.Add_Click({
    if (-not $script:SelectedVersion -or -not $script:SelectedLanguage) {
        [System.Windows.MessageBox]::Show(
            "Bitte Version und Sprache auswaehlen.",
            "OSDCloud - Auswahl erforderlich",
            "OK",
            "Information"
        ) | Out-Null
        return
    }

    $v = $script:SelectedVersion
    $l = $script:SelectedLanguage
    $displayName = "$OSVersionName $($v.Build) $OSEdition ($($l.Label))"

    $confirmResult = [System.Windows.MessageBox]::Show(
        "Soll folgende Konfiguration installiert werden?`n`n$displayName`n`nDas System wird formatiert und automatisch neu gestartet.",
        "OSDCloud - Confirm Deployment",
        "YesNo",
        "Warning"
    )

    if ($confirmResult -eq "Yes") {
        $SelectedConfig = @{
            DisplayName = $displayName
            OSVersion   = $OSVersionName
            OSBuild     = $v.Build
            OSEdition   = $OSEdition
            OSLanguage  = $l.Tag
            OSLicense   = $OSLicense
        }

        $window.Close()
        Start-OSDeployment -Config $SelectedConfig

        Read-Host -Prompt "Press Enter to exit"
    }
})

# Cancel Button Click
$btnCancel.Add_Click({
    $window.Close()
})

#endregion Event Handlers

#region Show Window

try {
    $null = $window.ShowDialog()
}
catch {
    Write-Error "Failed to show GUI. Error: $($_.Exception.Message)"
    exit 1
}

#endregion Show Window
