param(
  [Parameter(Mandatory = $true)]
  [string] $ContractId,

  [Parameter(Mandatory = $true)]
  [string] $Admin,

  [Parameter(Mandatory = $true)]
  [string] $Issuer,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9a-fA-F]{64}$')]
  [string] $MetadataHash,

  [string] $Network = "testnet"
)

$ErrorActionPreference = "Stop"

$tempFile = New-TemporaryFile
try {
  $bytes = [byte[]]::new(32)
  for ($i = 0; $i -lt 32; $i++) {
    $bytes[$i] = [Convert]::ToByte($MetadataHash.Substring($i * 2, 2), 16)
  }
  [IO.File]::WriteAllBytes($tempFile.FullName, $bytes)

  stellar contract invoke `
    --id $ContractId `
    --source $Admin `
    --network $Network `
    -- add_issuer `
    --admin $Admin `
    --issuer $Issuer `
    --metadata_hash-file-path $tempFile.FullName
}
finally {
  Remove-Item -LiteralPath $tempFile.FullName -Force -ErrorAction SilentlyContinue
}
