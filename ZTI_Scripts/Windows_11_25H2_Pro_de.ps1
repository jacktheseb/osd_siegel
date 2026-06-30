#================================================
#   [PreOS] Update Module
#================================================

if ((Get-MyComputerModel) -match 'Virtual') {
    Write-Host -ForegroundColor Green "Setting Display Resolution to 1600"
    Set-DisRes 1600
}

Write-Host -ForegroundColor Green "Updating OSD PowerShell Module"
Install-Module OSD -Force

Write-Host -ForegroundColor Green "Importing OSD PowerShell Module"
Import-Module OSD -Force


#================================================
#   [OSDCloud] Global Variables and Parameters
#================================================

$Params = @{
    OSVersion  = "Windows 11"
    OSBuild    = "25H2"
    OSEdition  = "Pro"
    OSLanguage = "de-de"
    OSLicense  = "Retail"
    ZTI        = $true
    Firmware   = $true
}

$Product = Get-MyComputerProduct
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


#================================================
#   [OSDCloud] Driver Pack Detection
#================================================

Write-Host -ForegroundColor Green "Detecting OSDCloud Driver Pack"

$DriverPack = Get-OSDCloudDriverPack `
    -Product $Product `
    -OSVersion $Params.OSVersion `
    -OSReleaseID $Params.OSBuild

if ($DriverPack) {
    $Global:MyOSDCloud.DriverPackName = $DriverPack.Name
    Write-Host -ForegroundColor Green "Driver Pack detected: $($DriverPack.Name)"
}
else {
    Write-Host -ForegroundColor Yellow "No matching Driver Pack detected"
}


#================================================
#   [OSDCloud] HP Support
#================================================

if (Test-HPIASupport) {
    Write-SectionHeader -Message "Detected HP Device, Enabling HPIA, HP BIOS and HP TPM Updates"

    $Global:MyOSDCloud.HPTPMUpdate  = [bool]$true
    $Global:MyOSDCloud.HPBIOSUpdate = [bool]$true

    if ($Product -ne '83B2' -and $Model -notmatch "zbook") {
        $Global:MyOSDCloud.HPIAALL = [bool]$true
    }
}


#================================================
#   [OSDCloud] Show Current Configuration
#================================================

Write-Host -ForegroundColor Green "Current OSDCloud Configuration:"
$Global:MyOSDCloud


#================================================
#   [OS] Start OSDCloud
#================================================

Write-Host -ForegroundColor Green "Starting OSDCloud"

Start-OSDCloud @Params


#================================================
#   [PostOS] Detect Offline Windows Drive
#================================================

Write-Host -ForegroundColor Green "Detecting offline Windows installation drive"

$WindowsDrive = Get-Volume |
    Where-Object {
        $_.DriveLetter -and
        (Test-Path "$($_.DriveLetter):\Windows\System32\Config\SOFTWARE")
    } |
    Select-Object -First 1 -ExpandProperty DriveLetter

if (-not $WindowsDrive) {
    Write-Host -ForegroundColor Yellow "Could not auto-detect Windows drive. Falling back to C:"
    $WindowsDrive = "C"
}

$WindowsPath = "$WindowsDrive`:"

Write-Host -ForegroundColor Green "Using Windows drive: $WindowsPath"


#================================================
#   [PostOS] Prepare Required Folders
#================================================

$OSDeployPath         = "$WindowsPath\ProgramData\OSDeploy"
$WindowsSetupScripts = "$WindowsPath\Windows\Setup\Scripts"

Write-Host -ForegroundColor Green "Creating required folders"

if (!(Test-Path $OSDeployPath)) {
    New-Item -Path $OSDeployPath -ItemType Directory -Force | Out-Null
}

if (!(Test-Path $WindowsSetupScripts)) {
    New-Item -Path $WindowsSetupScripts -ItemType Directory -Force | Out-Null
}


#================================================
#   [PostOS] Copy registerautopilot.ps1 from WinPE
#================================================

Write-Host -ForegroundColor Green "Copy embedded registerautopilot.ps1 from WinPE to local Windows installation"

$WinPERegisterAutopilotScript = "X:\OSDCloud\Config\Scripts\registerautopilot.ps1"
$LocalRegisterAutopilotScript = "$WindowsSetupScripts\registerautopilot.ps1"

if (Test-Path $WinPERegisterAutopilotScript) {
    Copy-Item `
        -Path $WinPERegisterAutopilotScript `
        -Destination $LocalRegisterAutopilotScript `
        -Force

    Write-Host -ForegroundColor Green "Copied registerautopilot.ps1 to $LocalRegisterAutopilotScript"
}
else {
    Write-Host -ForegroundColor Red "registerautopilot.ps1 was not found at $WinPERegisterAutopilotScript"
    throw "Required script missing in WinPE: $WinPERegisterAutopilotScript"
}


#================================================
#  [PostOS] OOBEDeploy Configuration
#================================================

Write-Host -ForegroundColor Green "Create OSDeploy.OOBEDeploy.json"

$OOBEDeployJson = @'
{
    "AddNetFX3":  {
                      "IsPresent":  true
                  },
    "Autopilot":  {
                      "IsPresent":  false
                  },
    "UpdateDrivers":  {
                          "IsPresent":  true
                      },
    "UpdateWindows":  {
                          "IsPresent":  true
                      }
}
'@

$OOBEDeployJson | Out-File `
    -FilePath "$OSDeployPath\OSDeploy.OOBEDeploy.json" `
    -Encoding ascii `
    -Force


#================================================
#  [PostOS] AutopilotOOBE Configuration Staging
#================================================

Write-Host -ForegroundColor Green "Define Computername from Serial Number"

try {
    $Serial = Get-WmiObject Win32_BIOS | Select-Object -ExpandProperty SerialNumber
}
catch {
    $Serial = Get-CimInstance Win32_BIOS | Select-Object -ExpandProperty SerialNumber
}

$TargetComputername  = $Serial
$AssignedComputerName = "$TargetComputername"

Write-Host -ForegroundColor Red "Assigned Computer Name: $AssignedComputerName"
Write-Host ""

Write-Host -ForegroundColor Green "Create OSDeploy.AutopilotOOBE.json"

$AutopilotOOBEJson = @"
{
    "AssignedComputerName" : "$AssignedComputerName",
    "AddToGroup":  "AutoPilotClients",
    "Assign":  {
                   "IsPresent":  true
               },
    "GroupTag":  "Siegel",
    "Hidden":  [
                   "AddToGroup",
                   "AssignedUser",
                   "PostAction",
                   "GroupTag",
                   "Assign"
               ],
    "PostAction":  "Quit",
    "Run":  "NetworkingWireless",
    "Docs":  "https://google.com/",
    "Title":  "Autopilot Manual Register"
}
"@

$AutopilotOOBEJson | Out-File `
    -FilePath "$OSDeployPath\OSDeploy.AutopilotOOBE.json" `
    -Encoding ascii `
    -Force


#================================================
#  [PostOS] Download additional OOBE scripts
#================================================

Write-Host -ForegroundColor Green "Downloading additional scripts for OOBE phase"

Invoke-RestMethod "https://raw.githubusercontent.com/jacktheseb/osd_siegel/refs/heads/main/Set-KeyboardLanguage.ps1" |
    Out-File -FilePath "$WindowsSetupScripts\keyboard.ps1" -Encoding ascii -Force

#================================================
#  [PostOS] OOBE CMD Command Line
#================================================

Write-Host -ForegroundColor Green "Creating oobe.cmd"

$OOBECMD = @'
@echo off

REM ==================================================
REM OOBE startup script
REM registerautopilot.ps1 must run first
REM ==================================================

echo Running keyboard configuration...
start /wait powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\keyboard.ps1

REM Debug PowerShell session if needed
REM start /wait powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass

exit /b 0
'@

$OOBECMD | Out-File `
    -FilePath "$WindowsSetupScripts\oobe.cmd" `
    -Encoding ascii `
    -Force


#================================================
#  [Optional] Create SetupComplete.cmd
#================================================
# This is only needed if you want to run something before normal OOBE.
# Currently disabled because registerautopilot.ps1 is already called first in oobe.cmd.
#
# If you want to enable it, remove the comment block below.

Write-Host -ForegroundColor Green "Creating SetupComplete.cmd"

$SetupCompleteCMD = @'
@echo off

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\registerautopilot.ps1

exit /b 0
'@

$SetupCompleteCMD | Out-File `
    -FilePath "$WindowsSetupScripts\SetupComplete.cmd" `
    -Encoding ascii `
    -Force


#================================================
#   [PostOS] Final Validation
#================================================

Write-Host -ForegroundColor Green "Validating staged files"

$RequiredFiles = @(
    "$WindowsSetupScripts\registerautopilot.ps1",
    "$WindowsSetupScripts\keyboard.ps1",
    "$WindowsSetupScripts\autopilotprereq.ps1",
    "$WindowsSetupScripts\autopilotoobe.ps1",
    "$WindowsSetupScripts\oobe.cmd",
    "$OSDeployPath\OSDeploy.OOBEDeploy.json",
    "$OSDeployPath\OSDeploy.AutopilotOOBE.json"
)

foreach ($File in $RequiredFiles) {
    if (Test-Path $File) {
        Write-Host -ForegroundColor Green "OK: $File"
    }
    else {
        Write-Host -ForegroundColor Red "Missing: $File"
    }
}


#================================================
#   Restart Computer
#================================================

Write-Host -ForegroundColor Green "Restarting in 20 seconds!"
Start-Sleep -Seconds 20

wpeutil reboot
