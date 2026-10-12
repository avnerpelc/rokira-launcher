param(
  [Parameter(Mandatory=$true)][string]$ElectronRuntime,
  [Parameter(Mandatory=$true)][string]$OutputDirectory,
  [Parameter(Mandatory=$true)][string]$ManifestUrl
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$runtime = (Resolve-Path -LiteralPath $ElectronRuntime).Path
$releasesRoot = [System.IO.Path]::GetFullPath((Join-Path $source 'releases'))
$output = [System.IO.Path]::GetFullPath($OutputDirectory)
$prefix = $releasesRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if (-not $output.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'A saída precisa ficar em launcher/releases.' }
if (Test-Path -LiteralPath $output) { throw 'A pasta de saída já existe; use uma pasta nova.' }

$parsedUrl = [Uri]$ManifestUrl
if ($parsedUrl.Scheme -ne 'https') { throw 'O manifesto precisa usar HTTPS.' }
$runtimeExe = Join-Path $runtime 'Ragnarok Classico.exe'
$defaultApp = Join-Path $runtime 'resources/default_app.asar'
if (-not (Test-Path -LiteralPath $runtimeExe -PathType Leaf) -or -not (Test-Path -LiteralPath $defaultApp -PathType Leaf)) {
  throw 'O runtime Electron não contém os arquivos necessários para montar o launcher.'
}

New-Item -ItemType Directory -Path $output -Force | Out-Null
Get-ChildItem -LiteralPath $runtime -Force | Where-Object { $_.Name -notin @('Ragnarok Classico.exe','resources') } | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination $output -Recurse -Force
}
New-Item -ItemType Directory -Path (Join-Path $output 'resources/app') -Force | Out-Null
Copy-Item -LiteralPath $defaultApp -Destination (Join-Path $output 'resources/default_app.asar') -Force
foreach ($name in @('main.cjs','preload.cjs','protocol.cjs','index.html','news.json','package.json','logo.png','background.png','Install-ClientPackage.ps1')) {
  Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $output "resources/app/$name") -Force
}
Copy-Item -LiteralPath $runtimeExe -Destination (Join-Path $output 'Rokira Launcher.exe') -Force
@{ manifestUrl = $parsedUrl.AbsoluteUri } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'resources/app/launcher-config.json') -Encoding utf8

$launcherZip = "$output.zip"
if (Test-Path -LiteralPath $launcherZip) { throw 'O ZIP de saída já existe; use uma pasta nova.' }
Compress-Archive -Path (Join-Path $output '*') -DestinationPath $launcherZip -CompressionLevel Optimal
Write-Host "Launcher compilado em $output"
Write-Host "Pacote pronto para distribuir em $launcherZip"
