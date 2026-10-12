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
