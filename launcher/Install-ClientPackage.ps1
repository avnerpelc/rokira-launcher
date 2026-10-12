param(
  [Parameter(Mandatory=$true)][string]$ZipPath,
  [Parameter(Mandatory=$true)][string]$InstallRoot,
  [Parameter(Mandatory=$true)][ValidateSet('base','patch')][string]$Channel
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archivePath = (Resolve-Path -LiteralPath $ZipPath).Path
$root = [System.IO.Path]::GetFullPath($InstallRoot)
$prefix = 'Rokira/'
$allowedRoots = @('cliente-windows','client-assets','client-browser','catalogo','localization','patch')
$blockedSegments = @('private','database','server','backup','backups','logs','log','downloads','accounts','account','contas','conta','secrets','secret','admin','administration','gm','game-master','ssh','keys','credentials')
$requiredPacketver = 20250402
$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)

try {
  if ($archive.Entries.Count -gt 50000) { throw 'O pacote tem arquivos demais.' }
  $files = [System.Collections.Generic.List[System.IO.Compression.ZipArchiveEntry]]::new()
  $totalSize = [long]0
  foreach ($entry in $archive.Entries) {
    $name = $entry.FullName.Replace('\','/')
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    if ($name.StartsWith('/') -or $name -match '(^|/)\.\.(/|$)' -or $name.Contains(':')) { throw 'O pacote contém um caminho inválido.' }
    if (-not $name.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'O pacote contém arquivos fora da pasta do cliente.' }
    $relative = $name.Substring($prefix.Length)
    $parts = @($relative -split '/')
    if ($parts | Where-Object { $blockedSegments -contains $_.ToLowerInvariant() }) { throw 'O pacote inclui dados internos que não podem ser distribuídos.' }
    $leaf = [System.IO.Path]::GetFileName($relative)
    if ($leaf -match '^(\.env($|\.)|CONTAS?(\.|$)|.*(credentials?|secrets?|password|senha|ssh|gm|admin)).*$' -or $leaf -match '\.(cnf|key|pem|ppk|p12|pfx)$') { throw 'O pacote inclui uma configuração privada ou administrativa.' }
    $allowed = $relative -match '^(Jogar\.(cmd|ps1)|clientinfo\.xml|client-version\.json)$' -or ($allowedRoots | Where-Object { $relative.StartsWith($_ + '/') })
    if (-not $allowed) { throw 'O pacote contém um componente que não pertence ao cliente.' }
    if ($name.EndsWith('/')) { continue }
    if (-not $seen.Add($name)) { throw 'O pacote contém caminhos duplicados.' }
    $totalSize += $entry.Length
    if ($totalSize -gt 5GB) { throw 'O pacote excede o limite de instalação.' }
    $files.Add($entry)
  }

  if ($files.Count -eq 0) { throw 'O pacote está vazio.' }
  if ($Channel -eq 'base') {
    if (-not ($files | Where-Object { $_.FullName -match '^Rokira/cliente-windows/Ragnarok Classico\.exe$' })) { throw 'O pacote base não contém o executável do jogo.' }
    if (-not ($files | Where-Object { $_.FullName -match '^Rokira/client-assets/index\.html$' })) { throw 'O pacote base não contém os arquivos do cliente.' }
    $metadataEntry = $files | Where-Object { $_.FullName -ceq 'Rokira/client-version.json' } | Select-Object -First 1
    if (-not $metadataEntry) { throw 'O pacote base não declara a versão de protocolo do cliente.' }
    $metadataReader = [IO.StreamReader]::new($metadataEntry.Open())
    try { $metadata = $metadataReader.ReadToEnd() | ConvertFrom-Json } finally { $metadataReader.Dispose() }
    if ($metadata.packetver -ne $requiredPacketver) { throw "O pacote não é compatível: esperado PACKETVER=$requiredPacketver." }
  }

  [System.IO.Directory]::CreateDirectory($root) | Out-Null
  $rootPrefix = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
  foreach ($entry in $files) {
    $relative = $entry.FullName.Substring($prefix.Length).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $destination = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($root, 'Rokira', $relative))
    if (-not $destination.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'O pacote contém um caminho fora da instalação.' }
    $directory = [System.IO.Path]::GetDirectoryName($destination)
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    $current = $directory
    while ($current.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
      if (Test-Path -LiteralPath $current) {
        $item = Get-Item -LiteralPath $current -Force
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw 'A instalação contém um link de pasta não permitido.' }
      }
      $parent = [System.IO.Path]::GetDirectoryName($current)
      if ($parent -eq $current -or -not $parent) { break }
      $current = $parent
    }
    if (Test-Path -LiteralPath $destination) {
      $existing = Get-Item -LiteralPath $destination -Force
      if ($existing.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw 'A instalação contém um link de arquivo não permitido.' }
    }
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination, $true)
  }
} finally {
  $archive.Dispose()
}
