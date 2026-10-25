param([string]$Python = "python")
$ErrorActionPreference = "Stop"
if ($env:OS -ne "Windows_NT") { throw "Windows is required to build this secondary edition." }
$Root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$Dist = Join-Path $Root "dist"
$Build = Join-Path $Root ".build"
New-Item -ItemType Directory -Force -Path $Dist, $Build | Out-Null
function Invoke-Python {
    param([string[]]$Arguments)
    & $Python @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Python command failed with exit code $LASTEXITCODE" }
}
Invoke-Python -Arguments @(
    "-m", "PyInstaller", "--noconfirm", "--clean", "--onefile",
    "--name", "autodl_watch", "--collect-all", "playwright", "--hidden-import", "greenlet",
    "--distpath", $Dist, "--workpath", (Join-Path $Build "worker"), "--specpath", $Build,
    (Join-Path $Root "src/autodl_watch.py")
)
Invoke-Python -Arguments @(
    "-m", "PyInstaller", "--noconfirm", "--clean", "--onedir", "--noconsole",
    "--name", "AutoDLMonitor-Windows", "--distpath", $Dist,
    "--workpath", (Join-Path $Build "gui"), "--specpath", $Build,
    (Join-Path $Root "src/windows_app.py")
)
$App = Join-Path $Dist "AutoDLMonitor-Windows"
Copy-Item (Join-Path $Dist "autodl_watch.exe") (Join-Path $App "autodl_watch.exe") -Force
Copy-Item (Join-Path $Root "WINDOWS-UNTESTED.md") (Join-Path $App "WINDOWS-UNTESTED.md") -Force
$Archive = Join-Path $Dist "AutoDLMonitor-Windows-secondary-UNTESTED.zip"
Compress-Archive -Path $App -DestinationPath $Archive -Force
$Digest = (Get-FileHash $Archive -Algorithm SHA256).Hash.ToLower()
[System.IO.File]::WriteAllText("$Archive.sha256", "$Digest  AutoDLMonitor-Windows-secondary-UNTESTED.zip" + [Environment]::NewLine)
Write-Output "Built secondary Windows edition. No real Windows desktop testing has been performed."
