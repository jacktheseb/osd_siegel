Add-Type -AssemblyName PresentationFramework

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="OSDCloud Menu" Height="300" Width="400">
  <StackPanel Margin="20">
    <TextBlock Text="OSDCloud Main Menu" FontSize="20" Foreground="DarkOrange" HorizontalAlignment="Center" Margin="0,0,0,20"/>
    <Button Name="btnZeroTouch" Content="Zero-Touch Installation" Height="40" Margin="0,0,0,10"/>
    <Button Name="btnCloudGUI" Content="OSD Cloud GUI" Height="40" Margin="0,0,0,10"/>
    <Button Name="btnExit" Content="Exit" Height="40"/>
  </StackPanel>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$Github = @{
    RepoOwner = "jacktheseb"
    RepoName = "osd_siegel"
    RepoFolder = "ZTI_Scripts"
}


# Import and install modules before showing the GUI
Import-Module OSD -Force
Install-Module OSD -Force

$btnZeroTouch = $window.FindName('btnZeroTouch')
$btnCloudGUI = $window.FindName('btnCloudGUI')
$btnExit = $window.FindName('btnExit')

$btnZeroTouch.Add_Click({
    $window.Close()
    Start-OSDPad -RepoOwner $Github.RepoOwner -RepoName $Github.RepoName -RepoFolder $Github.RepoFolder -BrandingTitle 'Cloud Deployment' -Hide Script
})

$btnCloudGUI.Add_Click({
    $window.Close()
    Start-OSDCloudGUI -BrandName "OSDeployment"
})

$btnExit.Add_Click({
    $window.Close()
    Exit
})

$window.ShowDialog() | Out-Null
