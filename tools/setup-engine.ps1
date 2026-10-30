$ErrorActionPreference = 'Stop'
$engineVersion = '4.7.2-stable'
$engineDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) '.engine'
$archiveName = "Godot_v${engineVersion}_win64.exe.zip"
$engineExecutable = Join-Path $engineDirectory "Godot_v${engineVersion}_win64.exe"
if (Test-Path -LiteralPath $engineExecutable) { Write-Output $engineExecutable; exit 0 }

# Discover the effective Windows proxy on every run. Never change system settings.
$settings = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$requestOptions = @{}
if ($settings.ProxyEnable -eq 1) {
    $route = $settings.ProxyServer
    if ($route -match '=') {
        $routes = @{}
        $route.Split(';') | ForEach-Object {
            $pair = $_.Split('=', 2)
            if ($pair.Count -eq 2) { $routes[$pair[0]] = $pair[1] }
        }
        $route = $routes['https']
        if (-not $route) { $route = $routes['http'] }
    }
    if (-not $route) { throw 'Enabled system proxy has no HTTPS route. No direct fallback.' }
    if ($route -notmatch '://') { $route = 'http://' + $route }
    $requestOptions.Proxy = $route
    Write-Output 'Using dynamically discovered Windows system proxy.'
} elseif ($settings.AutoConfigURL) {
    $sourceUri = [Uri]'https://github.com'
    $effective = [System.Net.WebRequest]::GetSystemWebProxy().GetProxy($sourceUri)
    if ($effective -eq $sourceUri) { throw 'PAC proxy could not be resolved. No direct fallback.' }
    $requestOptions.Proxy = $effective.AbsoluteUri
} else {
    Write-Output 'Using current system/environment/VPN routing.'
}
New-Item -ItemType Directory -Force -Path $engineDirectory | Out-Null
$releaseUrl = "https://github.com/godotengine/godot-builds/releases/download/$engineVersion"
$checksumFile = Join-Path $engineDirectory 'SHA512-SUMS.txt'
$archiveFile = Join-Path $engineDirectory $archiveName
Invoke-WebRequest -Uri "$releaseUrl/SHA512-SUMS.txt" @requestOptions -OutFile $checksumFile
Write-Output "Downloading official Godot $engineVersion..."
Invoke-WebRequest -Uri "$releaseUrl/$archiveName" @requestOptions -OutFile $archiveFile
$checksumLine = Get-Content -LiteralPath $checksumFile | Where-Object { $_.EndsWith("  $archiveName") }
if (-not $checksumLine) { throw 'Release checksum entry missing.' }
$expectedHash = ($checksumLine -split '\s+')[0]
if ((Get-FileHash -LiteralPath $archiveFile -Algorithm SHA512).Hash -ne $expectedHash) {
    throw 'Archive checksum mismatch. Installation aborted.'
}
Expand-Archive -LiteralPath $archiveFile -DestinationPath $engineDirectory -Force
Remove-Item -LiteralPath $archiveFile
Write-Output "SHA-512 verified. Engine: $engineExecutable"
