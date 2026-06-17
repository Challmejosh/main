$ErrorActionPreference = "Stop"

$target = Resolve-Path (Join-Path $PSScriptRoot "..\silent_witness\target")
$files = @{
  proof = Join-Path $target "proof"
  publicInputs = Join-Path $target "public_inputs"
  verificationKey = Join-Path $target "vk"
}

foreach ($entry in $files.GetEnumerator()) {
  if (!(Test-Path $entry.Value)) {
    throw "Missing $($entry.Key) artifact at $($entry.Value). Run build-silent-witness-wsl.ps1 first."
  }
}

function Convert-ToHex($Path) {
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  (($bytes | ForEach-Object { $_.ToString("x2") }) -join "")
}

[ordered]@{
  proof = Convert-ToHex $files.proof
  publicInputs = Convert-ToHex $files.publicInputs
  verificationKey = Convert-ToHex $files.verificationKey
} | ConvertTo-Json
