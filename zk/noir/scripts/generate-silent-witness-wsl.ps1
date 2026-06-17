param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9a-fA-F]{64}$')]
  [string] $VideoHash,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9]+$')]
  [string] $CredentialSecret,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9]+$')]
  [string] $NullifierSecret,

  [string] $OutputDir = ""
)

$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
if ($repo -notmatch "^([A-Za-z]):\\(.*)$") {
  throw "Expected a Windows absolute path, got $repo"
}

$drive = $Matches[1].ToLower()
$rest = $Matches[2] -replace "\\", "/"
$wslRepo = "/mnt/$drive/$rest"

$wslOutput = ""
if ($OutputDir) {
  $resolvedOutput = (Resolve-Path -LiteralPath $OutputDir -ErrorAction SilentlyContinue)
  if ($resolvedOutput) {
    $outputPath = $resolvedOutput.Path
  }
  else {
    $outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)
    New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
  }

  if ($outputPath -notmatch "^([A-Za-z]):\\(.*)$") {
    throw "Expected a Windows absolute output path, got $outputPath"
  }
  $outDrive = $Matches[1].ToLower()
  $outRest = $Matches[2] -replace "\\", "/"
  $wslOutput = "/mnt/$outDrive/$outRest"
}

$args = @(
  "chmod +x '$wslRepo/zk/noir/tools/jq' '$wslRepo/zk/noir/scripts/generate-silent-witness.sh'",
  "export PATH='$wslRepo/zk/noir/tools':/home/enliven/.nargo/bin:/home/enliven/.bb:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
  "cd '$wslRepo'",
  "bash zk/noir/scripts/generate-silent-witness.sh '$VideoHash' '$CredentialSecret' '$NullifierSecret'"
)

if ($wslOutput) {
  $args[-1] = "$($args[-1]) '$wslOutput'"
}

wsl bash -lc ($args -join "; ")
