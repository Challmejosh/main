param(
  [Parameter(Mandatory = $true)]
  [string] $ContractId,

  [Parameter(Mandatory = $true)]
  [string] $Admin,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9a-fA-F]{64}$')]
  [string] $CredentialRoot,

  [string] $Network = "testnet"
)

$ErrorActionPreference = "Stop"

$tempDir = New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString()))
try {
  $credentialRootPath = Join-Path $tempDir.FullName "credential_root.bin"
  $bytes = [byte[]]::new(32)
  for ($i = 0; $i -lt 32; $i++) {
    $bytes[$i] = [Convert]::ToByte($CredentialRoot.Substring($i * 2, 2), 16)
  }
  [IO.File]::WriteAllBytes($credentialRootPath, $bytes)

  stellar contract invoke `
    --id $ContractId `
    --source $Admin `
    --network $Network `
    -- revoke_credential_root `
    --admin $Admin `
    --credential_root-file-path $credentialRootPath
}
finally {
  Remove-Item -LiteralPath $tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
}
