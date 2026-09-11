#Requires -Version 5.1

<#
.SYNOPSIS
    OSDCloud OS Deployment Selector with Modern UI

.DESCRIPTION
    Modern WPF interface for selecting and deploying Windows OS versions
    using OSDCloud Zero-Touch Installation scripts.
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

#region OS Configuration Arrays

$OSConfigurations = @(
    @{
        DisplayName = "Windows 11 25H2 Pro (English)"
        OSVersion   = "Windows 11"
        OSBuild     = "25H2"
        OSEdition   = "Pro"
        OSLanguage  = "en-us"
        LanguageTag = "en"
    },
    @{
        DisplayName = "Windows 11 25H2 Pro (Deutsch)"
        OSVersion   = "Windows 11"
        OSBuild     = "25H2"
        OSEdition   = "Pro"
        OSLanguage  = "de-de"
        LanguageTag = "de"
    },
    @{
        DisplayName = "Windows 11 24H2 Pro (English)"
        OSVersion   = "Windows 11"
        OSBuild     = "24H2"
        OSEdition   = "Pro"
        OSLanguage  = "en-us"
        LanguageTag = "en"
    },
    @{
        DisplayName = "Windows 11 24H2 Pro (Deutsch)"
        OSVersion   = "Windows 11"
        OSBuild     = "24H2"
        OSEdition   = "Pro"
        OSLanguage  = "de-de"
        LanguageTag = "de"
    },
    @{
        DisplayName = "Windows 11 23H2 Pro (English)"
        OSVersion   = "Windows 11"
        OSBuild     = "23H2"
        OSEdition   = "Pro"
        OSLanguage  = "en-us"
        LanguageTag = "en"
    },
    @{
        DisplayName = "Windows 11 23H2 Pro (Deutsch)"
        OSVersion   = "Windows 11"
        OSBuild     = "23H2"
        OSEdition   = "Pro"
        OSLanguage  = "de-de"
        LanguageTag = "de"
    }
)

#endregion OS Configuration Arrays

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
        Install-Module OSD -Force -ErrorAction Stop

        Write-Host -ForegroundColor Green "Importing OSD PowerShell Module"
        Import-Module OSD -Force -ErrorAction Stop

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
            OSLicense  = "Retail"
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

#endregion Helper Functions

#region XAML UI Definition

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="OSDCloud OS Deployment Selector"
        Height="550"
        Width="700"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Background="#F5F5F5"
        Topmost="True"
        WindowStyle="SingleBorderWindow">

    <Window.Resources>
        <Style x:Key="ModernButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="#0078D4"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="16"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="20,15"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" 
                                CornerRadius="8"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" 
                                            VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#106EBE"/>
                                <Setter Property="Effect">
                                    <Setter.Value>
                                        <DropShadowEffect BlurRadius="10" 
                                                        ShadowDepth="3" 
                                                        Opacity="0.3"/>
                                    </Setter.Value>
                                </Setter>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#0D47A1"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="DeployButtonStyle" TargetType="Button" BasedOn="{StaticResource ModernButtonStyle}">
            <Setter Property="Background" Value="#107C10"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" 
                                CornerRadius="8"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" 
                                            VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#0B6A0B"/>
                                <Setter Property="Effect">
                                    <Setter.Value>
                                        <DropShadowEffect BlurRadius="10" 
                                                        ShadowDepth="3" 
                                                        Opacity="0.3"/>
                                    </Setter.Value>
                                </Setter>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#094009"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="ExitButtonStyle" TargetType="Button" BasedOn="{StaticResource ModernButtonStyle}">
            <Setter Property="Background" Value="#D13438"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" 
                                CornerRadius="8"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" 
                                            VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#A4373A"/>
                                <Setter Property="Effect">
                                    <Setter.Value>
                                        <DropShadowEffect BlurRadius="10" 
                                                        ShadowDepth="3" 
                                                        Opacity="0.3"/>
                                    </Setter.Value>
                                </Setter>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#752423"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="ModernComboBoxStyle" TargetType="ComboBox">
            <Setter Property="Background" Value="White"/>
            <Setter Property="Foreground" Value="#1F1F1F"/>
            <Setter Property="BorderBrush" Value="#C8C8C8"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,10"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Height" Value="40"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <Border Background="{TemplateBinding Background}"
                                    BorderBrush="{TemplateBinding BorderBrush}"
                                    BorderThickness="{TemplateBinding BorderThickness}"
                                    CornerRadius="6"
                                    Padding="{TemplateBinding Padding}">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <ContentPresenter Grid.Column="0" 
                                                    Content="{TemplateBinding SelectionBoxItem}"
                                                    ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                                    ContentStringFormat="{TemplateBinding SelectionBoxItemStringFormat}"
                                                    VerticalAlignment="Center"/>
                                    <ToggleButton Grid.Column="1" 
                                                Name="ToggleButton"
                                                IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"
                                                Background="Transparent"
                                                Foreground="#0078D4"
                                                FontSize="16"
                                                Content="▼"
                                                Padding="8,0,0,0"/>
                                </Grid>
                            </Border>
                            <Popup Name="PART_Popup"
                                    Placement="Bottom"
                                    IsOpen="{TemplateBinding IsDropDownOpen}"
                                    AllowsTransparency="True"
                                    Focusable="False"
                                    PopupAnimation="Fade">
                                <Border Background="White"
                                        BorderBrush="#C8C8C8"
                                        BorderThickness="1"
                                        CornerRadius="6"
                                        Padding="0"
                                        Margin="0,2,0,0"
                                        Effect="
                                            {
                                                <DropShadowEffect BlurRadius='5' ShadowDepth='2' Opacity='0.2'/>
                                            }">
                                    <ScrollViewer>
                                        <ItemsPresenter/>
                                    </ScrollViewer>
                                </Border>
                            </Popup>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid>
        <!-- Background Gradient -->
        <Grid.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                <GradientStop Color="#FFFFFF" Offset="0"/>
                <GradientStop Color="#F0F0F0" Offset="1"/>
            </LinearGradientBrush>
        </Grid.Background>

        <ScrollViewer VerticalScrollBarVisibility="Auto">
            <StackPanel Margin="40" VerticalAlignment="Top">
                <!-- Header Section -->
                <StackPanel HorizontalAlignment="Center" Margin="0,0,0,30">
                    <TextBlock Text="☁"
                               FontSize="48"
                               HorizontalAlignment="Center"
                               Foreground="#0078D4"
                               Margin="0,0,0,15"/>

                    <TextBlock Text="OSDCloud OS Deployment"
                               FontSize="32"
                               FontWeight="Bold"
                               HorizontalAlignment="Center"
                               Foreground="#1F1F1F"
                               Margin="0,0,0,10"/>

                    <TextBlock Text="Select and Deploy Windows OS Versions"
                               FontSize="14"
                               HorizontalAlignment="Center"
                               Foreground="#595959"
                               FontStyle="Italic"/>
                </StackPanel>

                <!-- Divider -->
                <Border Height="2" 
                        Background="#E0E0E0" 
                        Margin="0,0,0,30"
                        CornerRadius="1"/>

                <!-- OS Selection Section -->
                <StackPanel Spacing="20">
                    <!-- Label -->
                    <TextBlock Text="Available OS Versions:"
                               FontSize="16"
                               FontWeight="SemiBold"
                               Foreground="#1F1F1F"
                               Margin="0,0,0,5"/>

                    <!-- Dropdown -->
                    <ComboBox Name="cmbOSVersion"
                              Style="{StaticResource ModernComboBoxStyle}"
                              Background="White"/>

                    <!-- Details Panel -->
                    <Border Background="#F3F3F3"
                            BorderBrush="#E0E0E0"
                            BorderThickness="1"
                            CornerRadius="8"
                            Padding="16"
                            Margin="0,10,0,0">
                        <StackPanel Spacing="8">
                            <TextBlock Text="Configuration Details:"
                                       FontSize="13"
                                       FontWeight="Bold"
                                       Foreground="#0078D4"
                                       Margin="0,0,0,5"/>

                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="150"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Text="OS Version:"
                                           Grid.Column="0"
                                           FontWeight="SemiBold"
                                           Foreground="#1F1F1F"/>
                                <TextBlock Name="lblOSVersion"
                                           Grid.Column="1"
                                           Foreground="#595959"
                                           Text="Select an OS version"/>
                            </Grid>

                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="150"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Text="Build:"
                                           Grid.Column="0"
                                           FontWeight="SemiBold"
                                           Foreground="#1F1F1F"/>
                                <TextBlock Name="lblOSBuild"
                                           Grid.Column="1"
                                           Foreground="#595959"
                                           Text="-"/>
                            </Grid>

                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="150"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Text="Edition:"
                                           Grid.Column="0"
                                           FontWeight="SemiBold"
                                           Foreground="#1F1F1F"/>
                                <TextBlock Name="lblOSEdition"
                                           Grid.Column="1"
                                           Foreground="#595959"
                                           Text="-"/>
                            </Grid>

                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="150"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Text="Language:"
                                           Grid.Column="0"
                                           FontWeight="SemiBold"
                                           Foreground="#1F1F1F"/>
                                <TextBlock Name="lblOSLanguage"
                                           Grid.Column="1"
                                           Foreground="#595959"
                                           Text="-"/>
                            </Grid>
                        </StackPanel>
                    </Border>

                    <!-- Warning Box -->
                    <Border Background="#FFF4CE"
                            BorderBrush="#FFB900"
                            BorderThickness="1"
                            CornerRadius="8"
                            Padding="16"
                            Margin="0,10,0,0">
                        <StackPanel Spacing="5">
                            <TextBlock Text="⚠ Warning"
                                       FontWeight="Bold"
                                       Foreground="#B4009E"
                                       FontSize="13"/>
                            <TextBlock Text="OS deployment will format your system. Ensure all data is backed up before proceeding."
                                       Foreground="#595959"
                                       FontSize="12"
                                       TextWrapping="Wrap"/>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- Buttons Section -->
                <StackPanel Orientation="Horizontal" Spacing="15" Margin="0,30,0,0" HorizontalAlignment="Right">
                    <Button Name="btnDeploy"
                            Style="{StaticResource DeployButtonStyle}"
                            Width="160"
                            Height="45">
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center" HorizontalAlignment="Center">
                            <TextBlock Text="▶ " FontSize="16" Margin="0,0,8,0"/>
                            <TextBlock Text="Deploy" FontSize="14" FontWeight="SemiBold"/>
                        </StackPanel>
                    </Button>

                    <Button Name="btnCancel"
                            Style="{StaticResource ExitButtonStyle}"
                            Width="160"
                            Height="45">
                        <StackPanel Orientation="Horizontal" VerticalAlignment="Center" HorizontalAlignment="Center">
                            <TextBlock Text="✕ " FontSize="16" Margin="0,0,8,0"/>
                            <TextBlock Text="Cancel" FontSize="14" FontWeight="SemiBold"/>
                        </StackPanel>
                    </Button>
                </StackPanel>

                <!-- Footer -->
                <TextBlock Text="Cloud Deployment System © REWE digital GmbH"
                           FontSize="10"
                           Foreground="#8A8A8A"
                           HorizontalAlignment="Center"
                           Margin="0,40,0,0"/>
            </StackPanel>
        </ScrollViewer>
    </Grid>
</Window>
"@

#endregion XAML UI Definition

#region Load XAML

try {
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
}
catch {
    Write-Error "Failed to load XAML. Error: $($_.Exception.Message)"
    exit 1
}

#endregion Load XAML

#region Wire Up Controls

try {
    $cmbOSVersion = $window.FindName('cmbOSVersion')
    $btnDeploy = $window.FindName('btnDeploy')
    $btnCancel = $window.FindName('btnCancel')
    $lblOSVersion = $window.FindName('lblOSVersion')
    $lblOSBuild = $window.FindName('lblOSBuild')
    $lblOSEdition = $window.FindName('lblOSEdition')
    $lblOSLanguage = $window.FindName('lblOSLanguage')

    if (-not $cmbOSVersion -or -not $btnDeploy -or -not $btnCancel) {
        [System.Windows.MessageBox]::Show(
            "One or more GUI controls could not be found.",
            "OSDCloud - GUI Error",
            "OK",
            "Error"
        ) | Out-Null
        exit 1
    }

    # Populate ComboBox with OS configurations
    foreach ($config in $OSConfigurations) {
        [void]$cmbOSVersion.Items.Add($config)
    }

    # Set the default selection
    if ($cmbOSVersion.Items.Count -gt 0) {
        $cmbOSVersion.SelectedIndex = 0
    }
}
catch {
    Write-Error "Failed to wire up controls. Error: $($_.Exception.Message)"
    exit 1
}

#endregion Wire Up Controls

#region Event Handlers

# ComboBox Selection Changed
$cmbOSVersion.Add_SelectionChanged({
    if ($cmbOSVersion.SelectedItem) {
        $selectedConfig = $cmbOSVersion.SelectedItem
        $lblOSVersion.Text = $selectedConfig.OSVersion
        $lblOSBuild.Text = $selectedConfig.OSBuild
        $lblOSEdition.Text = $selectedConfig.OSEdition
        $lblOSLanguage.Text = if ($selectedConfig.LanguageTag -eq 'en') { 'English' } else { 'Deutsch' }
    }
})

# Deploy Button Click
$btnDeploy.Add_Click({
    if ($cmbOSVersion.SelectedItem) {
        $selectedConfig = $cmbOSVersion.SelectedItem
        
        $confirmResult = [System.Windows.MessageBox]::Show(
            "Are you sure you want to deploy: `n`n$($selectedConfig.DisplayName)?`n`nThis will format your system.",
            "OSDCloud - Confirm Deployment",
            "YesNo",
            "Warning"
        )

        if ($confirmResult -eq "Yes") {
            $window.Close()
            Start-OSDeployment -Config $selectedConfig
        }
    }
    else {
        [System.Windows.MessageBox]::Show(
            "Please select an OS version to deploy.",
            "OSDCloud - Selection Required",
            "OK",
            "Information"
        ) | Out-Null
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
