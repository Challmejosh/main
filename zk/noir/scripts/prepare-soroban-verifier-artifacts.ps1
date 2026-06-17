$ErrorActionPreference = "Stop"

$target = Resolve-Path (Join-Path $PSScriptRoot "..\silent_witness\target")
$vkPath = Join-Path $target "vk"
$sorobanVkPath = Join-Path $target "vk_soroban"

if (!(Test-Path $vkPath)) {
  throw "Missing VK artifact at $vkPath. Run build-silent-witness-wsl.ps1 first."
}

$vk = [System.IO.File]::ReadAllBytes($vkPath)
if ($vk.Length -eq 1764) {
  $stripped = [byte[]]::new(1760)
  [Array]::Copy($vk, 4, $stripped, 0, 1760)

  # bb 0.87 writes VK header u64 values as two 32-bit halves in reverse order.
  # The Soroban verifier expects big-endian u64 header words.
  for ($offset = 0; $offset -lt 32; $offset += 8) {
    $first = $stripped[$offset..($offset + 3)]
    $second = $stripped[($offset + 4)..($offset + 7)]
    [Array]::Copy($second, 0, $stripped, $offset, 4)
    [Array]::Copy($first, 0, $stripped, $offset + 4, 4)
  }

  [System.IO.File]::WriteAllBytes($sorobanVkPath, $stripped)
}
elseif ($vk.Length -eq 1760) {
  [System.IO.File]::WriteAllBytes($sorobanVkPath, $vk)
}
else {
  throw "Unexpected VK length $($vk.Length). Expected 1764 from bb or 1760 for Soroban verifier."
}

[ordered]@{
  vk = $vkPath
  vkBytes = $vk.Length
  sorobanVk = $sorobanVkPath
  sorobanVkBytes = ([System.IO.File]::ReadAllBytes($sorobanVkPath)).Length
  proof = Join-Path $target "proof"
  publicInputs = Join-Path $target "public_inputs"
} | ConvertTo-Json
