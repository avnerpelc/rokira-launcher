$ErrorActionPreference = 'Stop'
$paths = @(
  (Join-Path $PSScriptRoot '..\Build-Client-Release.ps1'),
  (Join-Path $PSScriptRoot '..\Install-ClientPackage.ps1'),
  (Join-Path $PSScriptRoot '..\Build-Rokira-Launcher.ps1')
)
foreach ($path in $paths) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $path), [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count) { throw ($errors | Out-String) }
}
Write-Output 'PowerShell scripts parse successfully.'

$id = [guid]::NewGuid().ToString('N')
$tempRoot = Join-Path $env:TEMP "rokira-launcher-smoke-$id"
$runtime = Join-Path $tempRoot 'electron-dist'
$releasesRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\releases'))
$output = Join-Path $releasesRoot "smoke-$id"
$zip = "$output.zip"
try {
  New-Item -ItemType Directory -Path (Join-Path $runtime 'resources') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $runtime 'locales') -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $runtime 'electron.exe') -Value 'mock-electron-runtime' -NoNewline
  Set-Content -LiteralPath (Join-Path $runtime 'resources/default_app.asar') -Value 'mock-default-app' -NoNewline
  Set-Content -LiteralPath (Join-Path $runtime 'resources.pak') -Value 'mock-electron-resources' -NoNewline
  Set-Content -LiteralPath (Join-Path $runtime 'locales/en-US.pak') -Value 'mock-electron-locale' -NoNewline
  $buildScript = Join-Path $PSScriptRoot '..\Build-Rokira-Launcher.ps1'
  & $buildScript -ElectronRuntime $runtime -OutputDirectory $output -ManifestUrl 'https://updates.example.invalid/rokira/manifest.json'

  foreach ($required in @(
    (Join-Path $output 'Rokira Launcher.exe'),
    (Join-Path $output 'resources.pak'),
    (Join-Path $output 'locales/en-US.pak'),
    (Join-Path $output 'resources/app/main.cjs'),
    (Join-Path $output 'resources/app/protocol.cjs'),
    (Join-Path $output 'resources/app/launcher-config.json'),
    $zip
  )) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Arquivo esperado ausente no pacote do launcher: $required" }
  }
  $configPath = Join-Path $output 'resources/app/launcher-config.json'
  $configBytes = [System.IO.File]::ReadAllBytes($configPath)
  if ($configBytes.Length -ge 3 -and $configBytes[0] -eq 0xEF -and $configBytes[1] -eq 0xBB -and $configBytes[2] -eq 0xBF) {
    throw 'A configuração do launcher foi gravada com BOM UTF-8 e não poderá ser lida pelo Node.'
  }
  $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
  if ($config.manifestUrl -ne 'https://updates.example.invalid/rokira/manifest.json') { throw 'O endereço HTTPS do manifesto não foi incorporado corretamente.' }
  Write-Output 'Launcher packaging smoke test passed.'
} finally {
  $resolvedReleases = [System.IO.Path]::GetFullPath($releasesRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
  $resolvedOutput = [System.IO.Path]::GetFullPath($output)
  if ($resolvedOutput.StartsWith($resolvedReleases, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedOutput)) {
    Remove-Item -LiteralPath $resolvedOutput -Recurse -Force
  }
  if ($resolvedOutput.StartsWith($resolvedReleases, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $zip)) {
    Remove-Item -LiteralPath $zip -Force
  }
  if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
