param(
  [Parameter(Mandatory=$true)][string]$SourceRoot,
  [Parameter(Mandatory=$true)][string]$OutputDirectory,
  [Parameter(Mandatory=$true)][string]$Version,
  [Parameter(Mandatory=$true)][ValidateSet('base','patch')][string]$Channel
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Use uma versão no formato 1.0.2.' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$output = (Resolve-Path -LiteralPath $OutputDirectory).Path
$zipPath = Join-Path $output "Rokira-$Channel-$Version.zip"
$releasePath = Join-Path $output "$Channel-release.json"
if ((Test-Path -LiteralPath $zipPath) -or (Test-Path -LiteralPath $releasePath)) {
  throw "A saída já existe. Escolha uma pasta nova: $output"
}
if ($Channel -eq 'base') {
  foreach ($relative in @('cliente-windows/Ragnarok Classico.exe','client-assets/index.html')) {
    if (-not (Test-Path -LiteralPath (Join-Path $source $relative) -PathType Leaf)) { throw "O cliente base não contém o arquivo necessário: $relative" }
  }
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$fileStream = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::CreateNew)
$archive = [System.IO.Compression.ZipArchive]::new($fileStream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
$allowedFolders = if ($Channel -eq 'base') { @('cliente-windows', 'client-assets', 'client-browser', 'catalogo', 'localization') } else { @('patch', 'cliente-windows', 'client-assets', 'client-browser', 'catalogo', 'localization') }
$rootFiles = if ($Channel -eq 'base') { @('Jogar.cmd', 'Jogar.ps1', 'clientinfo.xml') } else { @('clientinfo.xml') }
$excludedSegments = @('private', 'database', 'server', 'backup', 'backups', 'logs', 'log', 'downloads', 'accounts', 'account', 'contas', 'conta', 'secrets', 'secret', 'admin', 'administration', 'gm', 'game-master', 'ssh', 'keys', 'credentials')
$added = 0

function Test-PublicClientFile([string]$relative) {
  $segments = $relative -split '[\\/]'
  if ($segments | Where-Object { $excludedSegments -contains $_.ToLowerInvariant() }) { throw "Caminho privado/administrativo encontrado na origem: $relative" }
  $leaf = [System.IO.Path]::GetFileName($relative)
  if ($leaf -match '^\.env($|\.)' -or $leaf -match '(?i)(contas?|accounts?|credentials?|secrets?|password|senha|ssh|gm|admin)' -or $leaf -match '(?i)\.(cnf|key|pem|ppk|p12|pfx)$') { throw "Arquivo de conta, credencial ou acesso privilegiado encontrado: $relative" }
  if ($relative -match '(?i)(^|[\\/])(\.git|\.codex|\.vscode)([\\/]|$)' -or $leaf -match '(?i)(\.bak|\.old|\.log)$') { throw "Arquivo interno/temporário encontrado na origem: $relative" }
  return $true
}

function Add-ClientFile([string]$path, [string]$entryName) {
  $relative = $entryName.Substring('Rokira/'.Length)
  if (-not (Test-PublicClientFile $relative)) { return }
  $entry = $archive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
  $input = [System.IO.File]::OpenRead($path)
  $target = $entry.Open()
  try { $input.CopyTo($target) } finally { $target.Dispose(); $input.Dispose() }
  $script:added++
}

try {
  foreach ($name in $rootFiles) {
    $path = Join-Path $source $name
    if (Test-Path -LiteralPath $path -PathType Leaf) { Add-ClientFile $path "Rokira/$name" }
  }
  foreach ($folder in $allowedFolders) {
    $base = Join-Path $source $folder
    if (-not (Test-Path -LiteralPath $base -PathType Container)) { continue }
    $privatePath = Get-ChildItem -LiteralPath $base -Force -Recurse | Where-Object {
      $_.Attributes -band [IO.FileAttributes]::ReparsePoint -or
      ($_.PSIsContainer -and $_.Name.ToLowerInvariant() -in $excludedSegments) -or
      (-not $_.PSIsContainer -and -not (Test-PublicClientFile ([IO.Path]::GetRelativePath($source, $_.FullName))))
    } | Select-Object -First 1
    if ($privatePath) { throw "A origem contém um caminho privado/interno ou link: $($privatePath.FullName)" }
    Get-ChildItem -LiteralPath $base -File -Recurse -Force | ForEach-Object {
      $relative = [IO.Path]::GetRelativePath($source, $_.FullName).Replace('\','/')
      Add-ClientFile $_.FullName "Rokira/$relative"
    }
  }
} finally { $archive.Dispose() }

if ($added -lt 10) { Remove-Item -LiteralPath $zipPath -Force; throw 'O pacote ficou incompleto; confirme a pasta de origem.' }
$sha = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$size = (Get-Item -LiteralPath $zipPath).Length
$release = [ordered]@{
  channel = $Channel
  version = $Version
  contentPolicy = "rokira-$Channel-v1"
  packageUrl = "https://SEU-DOMINIO-DE-ATUALIZACAO/rokira/$Channel/Rokira-$Channel-$Version.zip"
  sha256 = $sha
  size = $size
}
$release | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $releasePath -Encoding utf8
Write-Host "Pacote limpo criado: $zipPath"
Write-Host "Arquivos incluídos: $added"
Write-Host "Tamanho: $size bytes"
Write-Host "SHA-256: $sha"
Write-Host "Metadados do pacote criados: $releasePath (complete URL antes de incorporar ao manifesto principal)."
