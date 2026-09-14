$Global:Transcript = "$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-Cleanup-Script.log"
Start-Transcript -Path (Join-Path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD\" $Global:Transcript) -ErrorAction Ignore

Write-Host "Execute OSD Cloud Cleanup Script" -ForegroundColor Green

# Copying the OOBEDeploy and AutopilotOOBE Logs
Get-ChildItem 'C:\Windows\Temp' -Filter *OOBE* | Copy-Item -Destination 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD' -Force

# Copying OSDCloud Logs
If (Test-Path -Path 'C:\OSDCloud\Logs') {
    Move-Item 'C:\OSDCloud\Logs\*.*' -Destination 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD' -Force
}
Move-Item 'C:\ProgramData\OSDeploy\*.*' -Destination 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD' -Force

If (Test-Path -Path 'C:\Temp') {
    Get-ChildItem 'C:\Temp' -Filter *OOBE* | Copy-Item -Destination 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD' -Force
    Get-ChildItem 'C:\Windows\Temp' -Filter *Events* | Copy-Item -Destination 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD' -Force
}

# Cleanup directories
If (Test-Path -Path 'C:\OSDCloud') { Remove-Item -Path 'C:\OSDCloud' -Recurse -Force }
If (Test-Path -Path 'C:\Drivers') { Remove-Item 'C:\Drivers' -Recurse -Force }
If (Test-Path -Path 'C:\Intel') { Remove-Item 'C:\Intel' -Recurse -Force }
If (Test-Path -Path 'C:\ProgramData\OSDeploy') { Remove-Item 'C:\ProgramData\OSDeploy' -Recurse -Force }

# Cleanup Scripts
Remove-Item C:\Windows\Setup\Scripts\*.* -Exclude *.TAG -Force | Out-Null

Stop-Transcript