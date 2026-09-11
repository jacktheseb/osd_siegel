#Requires -Version 5.1

<#
.SYNOPSIS
    OSDCloud WPF Menu

.DESCRIPTION
    Simple WPF menu for launching Zero-Touch Installation or OSDCloud GUI.
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

#region Module Handling

$ModuleName = 'OSD'

try {
    $installedModule = Get-Module -ListAvailable -Name $ModuleName

    if (-not $installedModule) {
        Write-Host "Module '$ModuleName' not found. Installing..." -ForegroundColor Yellow

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        Install-Module -Name $ModuleName `
            -Force `
            -Scope CurrentUser `
            -AllowClobber `
            -ErrorAction Stop
    }

    Import-Module -Name $ModuleName -Force -ErrorAction Stop

    Write-Host "Module '$ModuleName' loaded successfully." -ForegroundColor Green
}
catch {
    [System.Windows.MessageBox]::Show(
        "Failed to install or import module '$ModuleName'.`n`nError:`n$($_.Exception.Message)",
        "OSDCloud Menu - Module Error",
        "OK",
        "Error"
    ) | Out-Null

    exit 1
}

#endregion Module Handling

#region GitHub Configuration

$Github = @{
    RepoOwner  = "jacktheseb"
    RepoName   = "osd_siegel"
    RepoFolder = "ZTI_Scripts"
}

#endregion GitHub Configuration

#region OSDPad Hide Configuration

# Hide option for Start-OSDPad
# Common value: 'Script'
# If needed, change this to another valid value supported by Start-OSDPad.
$OSDPadHide = 'Script'

#endregion OSDPad Hide Configuration

#region Helper Function

function Start-ZeroTouchInstallation {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$GithubConfig,

        [Parameter(Mandatory = $false)]
        [string]$Hide = 'Script'
    )

    try {
        $command = Get-Command Start-OSDPad -ErrorAction Stop

        $params = @{
            RepoOwner     = $GithubConfig.RepoOwner
            RepoName      = $GithubConfig.RepoName
            RepoFolder    = $GithubConfig.RepoFolder
            BrandingTitle = 'Cloud Deployment'
        }

        if ($command.Parameters.ContainsKey('Hide')) {
            $params.Add('Hide', $Hide)
        }

        Start-OSDPad @params
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "Failed to start Zero-Touch Installation.`n`nError:`n$($_.Exception.Message)",
            "OSDCloud Menu - Error",
            "OK",
            "Error"
        ) | Out-Null
    }
}

#endregion Helper Function

#region XAML

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="OSDCloud Menu"
        Height="300"
        Width="400"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Background="#1E1E1E">

    <StackPanel Margin="20">

        <TextBlock Text="OSDCloud Main Menu"
                   FontSize="20"
                   FontWeight="Bold"
                   Foreground="DarkOrange"
                   HorizontalAlignment="Center"
                   Margin="0,0,0,20"/>

        <Button Name="btnZeroTouch"
                Content="Zero-Touch Installation"
                Height="40"
                Margin="0,0,0,10"/>

        <Button Name="btnCloudGUI"
                Content="OSD Cloud GUI"
                Height="40"
                Margin="0,0,0,10"/>

        <Button Name="btnExit"
                Content="Exit"
                Height="40"/>

    </StackPanel>
</Window>
"@

#endregion XAML

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

#region Controls

$btnZeroTouch = $window.FindName('btnZeroTouch')
$btnCloudGUI  = $window.FindName('btnCloudGUI')
$btnExit      = $window.FindName('btnExit')

if (-not $btnZeroTouch -or -not $btnCloudGUI -or -not $btnExit) {
    [System.Windows.MessageBox]::Show(
        "One or more GUI controls could not be found.",
        "OSDCloud Menu - GUI Error",
        "OK",
        "Error"
    ) | Out-Null

    exit 1
}

#endregion Controls

#region Button Events

$btnZeroTouch.Add_Click({
    $window.Close()

    Start-ZeroTouchInstallation `
        -GithubConfig $Github `
        -Hide $OSDPadHide
})

$btnCloudGUI.Add_Click({
    try {
        $window.Close()

        Start-OSDCloudGUI -BrandName "OSDeployment"
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "Failed to start OSDCloud GUI.`n`nError:`n$($_.Exception.Message)",
            "OSDCloud Menu - Error",
            "OK",
            "Error"
        ) | Out-Null
    }
})

$btnExit.Add_Click({
    $window.Close()
})

#endregion Button Events

#region Show Window

try {
    $null = $window.ShowDialog()
}
catch {
    Write-Error "Failed to show GUI. Error: $($_.Exception.Message)"
    exit 1
}

#endregion Show Window
