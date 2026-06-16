param(
  [Parameter(Mandatory = $true)]
  [string] $ContractId,

  [Parameter(Mandatory = $true)]
  [string] $Source,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9a-fA-F]{64}$')]
  [string] $VideoHash,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9a-fA-F]{64}$')]
  [string] $MetadataHash,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9a-fA-F]{64}$')]
  [string] $ProofId,

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

  $videoPath = Write-HexBytes "video_hash.bin" $VideoHash
  $metadataPath = Write-HexBytes "metadata_hash.bin" $MetadataHash
  $proofPath = Write-HexBytes "proof_id.bin" $ProofId

  stellar contract invoke `
    --id $ContractId `
    --source $Source `
    --network $Network `
    -- register_source `
    --source $Source `
    --video_hash-file-path $videoPath `
    --metadata_hash-file-path $metadataPath `
    --proof_id-file-path $proofPath
}
finally {
  Remove-Item -LiteralPath $tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
}
