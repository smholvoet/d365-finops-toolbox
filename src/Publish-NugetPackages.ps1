$LatestNugetInstall = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
$packageSource = "https://pkgs.dev.azure.com/<org>/<project>/_packaging/<artifact-feed>/nuget/v3/index.json"
$NugetPackagesFolder = "C:\Users\<...>\nuget"

# Point to directory containing NuGet files
Set-Location -Path $NugetPackagesFolder
if (-Not(Test-Path -Path $NugetPackagesFolder)) {
    Exit 1;
}

# Download latest nuget.exe CLI
Invoke-WebRequest -Uri $LatestNugetInstall -OutFile 'nuget.exe'

# Push packages to Azure Artifacts feed
$packages = Get-ChildItem | Where-Object {$_.Name -like "*.nupkg"}

foreach($package in $packages) {
    Write-Host "⬆ Uploading $($package) to artifact feed..."
    .\nuget.exe push -Source $packageSource `
                    -ApiKey az $package.name `
                    -Timeout 900
}
