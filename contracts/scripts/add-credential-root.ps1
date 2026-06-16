param(
  [Parameter(Mandatory = $true)]
  [string] $ContractId,

  [Parameter(Mandatory = $true)]
  [string] $Admin,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9a-fA-F]{64}$')]
  [string] $CredentialRoot,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9a-fA-F]{64}$')]
  [string] $MetadataHash,

  [string] $Network = "testnet"
)

$ErrorActionPreference = "Stop"

$tempDir = New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString()))
try {
  function Write-HexBytes($name, $hexValue) {
    $path = Join-Path $tempDir.FullName $name
    $bytes = [byte[]]::new(32)
    for ($i = 0; $i -lt 32; $i++) {
      $bytes[$i] = [Convert]::ToByte($hexValue.Substring($i * 2, 2), 16)
    }
    [IO.File]::WriteAllBytes($path, $bytes)
    return $path
  }

  $credentialRootPath = Write-HexBytes "credential_root.bin" $CredentialRoot
  $metadataPath = Write-HexBytes "metadata_hash.bin" $MetadataHash

  stellar contract invoke `
    --id $ContractId `
    --source $Admin `
    --network $Network `
    -- add_credential_root `
    --admin $Admin `
    --credential_root-file-path $credentialRootPath `
    --metadata_hash-file-path $metadataPath
}
finally {
  Remove-Item -LiteralPath $tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
}
