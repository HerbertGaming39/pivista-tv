# Start the PiVista TV launcher from Windows without a Raspberry Pi.
#
# It builds the production QML application inside WSL and WSLg shows the window
# on the Windows desktop.  The preview has its own settings directory, so it
# never touches a real Pi configuration or Windows settings.
#
#   .\tools\windows-preview.ps1
#   .\tools\windows-preview.ps1 -Reset
#   .\tools\windows-preview.ps1 -Width 1920 -Height 1080
#
param(
    [switch]$Reset,
    [string]$Distro = "Ubuntu",
    [int]$Width = 1280,
    [int]$Height = 720
)

$ErrorActionPreference = "Stop"
$project = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if ($project -notmatch '^([A-Za-z]):\\(.*)$') {
    throw "The preview must run from a local drive path, got: $project"
}
$linuxProject = "/mnt/$($Matches[1].ToLower())/$($Matches[2].Replace('\', '/'))"

# Check the distribution before invoking the Linux script, so a missing WSL
# install gives a useful message instead of a shell error.
$distros = (& wsl.exe -l -q 2>$null) -split "`r?`n" | ForEach-Object { $_.Trim() }
if (-not ($distros -contains $Distro)) {
    throw "WSL distro '$Distro' is not available. Install WSL2 with Ubuntu, or pass -Distro <name>."
}

$arguments = @("--width", "$Width", "--height", "$Height")
if ($Reset) {
    $arguments += "--reset"
}
& wsl.exe -d $Distro -- bash "$linuxProject/tools/preview-in-wsl.sh" @arguments
exit $LASTEXITCODE
