param(
  [string] $BackendUrl = "http://127.0.0.1:5050",
  [string] $ContractId = "CCKTQNMBLXZXMWVR2WG4HDDUI3QGJU5LV5NTLFPCB72UITWE5TEDK7BT",
  [string] $Source = "harpocrates-admin",
  [string] $Network = "testnet",
  [string] $CredentialSecret = "123456789",
  [string] $NullifierSecret = "987654321",
  [int] $StellarTimeoutSeconds = 180,
  [switch] $EnsureCredentialRoot,
  [switch] $RegisterOnChain
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Net.Http

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$backend = Join-Path $root "backend"
$frontend = Join-Path $root "frontend"
$contracts = Join-Path $root "contracts"
$runId = [Guid]::NewGuid().ToString("N")
$outDir = Join-Path $root "tmp\e2e-$runId"
New-Item -ItemType Directory -Force $outDir | Out-Null

function Write-Step($message) {
  Write-Host "[harpocrates-e2e] $message"
}

function Get-Sha256Hex($path) {
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
}

function Assert-Hex32($name, $value) {
  if ($value -notmatch '^[0-9a-fA-F]{64}$') {
    throw "$name must be a 32-byte hex string, got: $value"
  }
}

function ConvertTo-JsonMetadata($metadata) {
  return ($metadata | ConvertTo-Json -Depth 10 -Compress)
}

function Invoke-MultipartUpload($uri, $filePath, $fieldName, $fileName, $metadataJson, $outputPath) {
  $client = [System.Net.Http.HttpClient]::new()
  $form = [System.Net.Http.MultipartFormDataContent]::new()
  $fileStream = [IO.File]::OpenRead($filePath)
  try {
    $fileContent = [System.Net.Http.StreamContent]::new($fileStream)
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("video/mp4")
    $form.Add($fileContent, $fieldName, $fileName)
    if ($null -ne $metadataJson) {
      $form.Add([System.Net.Http.StringContent]::new($metadataJson), "metadata")
    }

    $response = $client.PostAsync($uri, $form).GetAwaiter().GetResult()
    $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
    if (!$response.IsSuccessStatusCode) {
      $body = [Text.Encoding]::UTF8.GetString($bytes)
      throw "multipart request failed with status $($response.StatusCode): $body"
    }
    if ($outputPath) {
      [IO.File]::WriteAllBytes($outputPath, $bytes)
    }
    return $response
  }
  finally {
    $form.Dispose()
    $fileStream.Dispose()
    $client.Dispose()
  }
}

function Invoke-MultipartJson($uri, $filePath, $fieldName, $fileName) {
  $tempPath = Join-Path $outDir ([Guid]::NewGuid().ToString("N") + ".json")
  $response = Invoke-MultipartUpload $uri $filePath $fieldName $fileName $null $tempPath
  try {
    return (Get-Content -Raw -LiteralPath $tempPath | ConvertFrom-Json)
  }
  finally {
    $response.Dispose()
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
  }
}

function Get-HeaderValue($response, $name) {
  $values = [string[]]::new(0)
  if ($response.Headers.TryGetValues($name, [ref]$values)) {
    return $values[0]
  }
  if ($response.Content.Headers.TryGetValues($name, [ref]$values)) {
    return $values[0]
  }
  return $null
}

function Invoke-PowerShellFile($scriptPath, [string[]] $arguments, $workingDirectory, $label) {
  $stdoutPath = Join-Path $outDir ([Guid]::NewGuid().ToString("N") + ".stdout.log")
  $stderrPath = Join-Path $outDir ([Guid]::NewGuid().ToString("N") + ".stderr.log")
  $processArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath) + $arguments
  $process = Start-Process `
    -FilePath "powershell.exe" `
    -ArgumentList $processArguments `
    -WorkingDirectory $workingDirectory `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath `
    -WindowStyle Hidden `
    -Wait `
    -PassThru
  $stdout = Get-Content -Raw -LiteralPath $stdoutPath -ErrorAction SilentlyContinue
  $stderr = Get-Content -Raw -LiteralPath $stderrPath -ErrorAction SilentlyContinue
  if ($process.ExitCode -ne 0) {
    throw "$label failed with exit code $($process.ExitCode). stdout: $stdout stderr: $stderr"
  }
  return @{
    stdout = $stdout
    stderr = $stderr
  }
}

try {
  Write-Step "checking backend health at $BackendUrl"
  $health = Invoke-RestMethod -Method Get -Uri "$BackendUrl/health" -TimeoutSec 15
  if (!$health.ok) {
    throw "backend health check did not return ok"
  }

  Write-Step "creating synthetic source video"
  $sourceVideo = Join-Path $outDir "source.mp4"
  & ffmpeg -y -v error -f lavfi -i "testsrc=size=320x240:rate=30" -t 3 -pix_fmt yuv420p $sourceVideo
  if ($LASTEXITCODE -ne 0) {
    throw "ffmpeg failed while creating the source video"
  }
  $sourceHash = Get-Sha256Hex $sourceVideo

  $proofId = (Get-FileHash -Algorithm SHA256 -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes("$sourceHash`:$runId")))).Hash.ToLowerInvariant()
  $timestamp = (Get-Date).ToUniversalTime().ToString("o")
  $metadata = [ordered]@{
    protocol = "harpocrates"
    version = 1
    tier = "silent"
    sourceHash = $sourceHash
    proofId = $proofId
    timestamp = $timestamp
    fileName = "source.mp4"
    testRun = $runId
  }
  $metadataJson = ConvertTo-JsonMetadata $metadata

  Write-Step "embedding metadata through Flask steganography endpoint"
  $embeddedVideo = Join-Path $outDir "embedded.mp4"
  $embedResponse = Invoke-MultipartUpload "$BackendUrl/api/stego/embed" $sourceVideo "video" "source.mp4" $metadataJson $embeddedVideo

  $embeddedHash = Get-Sha256Hex $embeddedVideo
  $headerEmbeddedHash = Get-HeaderValue $embedResponse "X-Harpocrates-Embedded-Hash"
  $metadataHash = Get-HeaderValue $embedResponse "X-Harpocrates-Metadata-Hash"
  $embedResponse.Dispose()
  Assert-Hex32 "embedded hash" $embeddedHash
  Assert-Hex32 "metadata hash" $metadataHash
  if ($headerEmbeddedHash -ne $embeddedHash) {
    throw "embedded hash header does not match downloaded video hash"
  }

  Write-Step "extracting metadata from embedded video"
  $extractResponse = Invoke-MultipartJson "$BackendUrl/api/stego/extract" $embeddedVideo "video" "embedded.mp4"
  if ($extractResponse.metadata.protocol -ne "harpocrates") {
    throw "extract endpoint did not recover Harpocrates metadata"
  }
  if ($extractResponse.metadata.proofId -ne $proofId) {
    throw "extracted proof id does not match"
  }

  Write-Step "generating browser-compatible Noir UltraHonk proof"
  $proofDir = Join-Path $outDir "proof"
  Push-Location $frontend
  try {
    $proofJsonRaw = & npm run --silent proof:noir-client -- `
      --videoHash $embeddedHash `
      --credentialSecret $CredentialSecret `
      --nullifierSecret $NullifierSecret `
      --outDir $proofDir
    if ($LASTEXITCODE -ne 0) {
      throw "Noir client proof generation failed"
    }
  }
  finally {
    Pop-Location
  }
  $proofJson = $proofJsonRaw | Select-Object -Last 1 | ConvertFrom-Json
  if (!$proofJson.verified) {
    throw "Noir proof did not verify locally"
  }

  $txHash = $null
  $txStatus = "LOCAL_ONLY"
  $chainRecord = $null
  if ($RegisterOnChain) {
    if ($EnsureCredentialRoot) {
      Write-Step "ensuring Silent Witness credential root is active on Stellar $Network"
      $credentialRootMetadataHash = (Get-FileHash -Algorithm SHA256 -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes("credential-root:$($proofJson.credentialRoot)")))).Hash.ToLowerInvariant()
      Invoke-PowerShellFile `
        (Join-Path $contracts "scripts\add-credential-root.ps1") `
        @(
          "-ContractId",
          $ContractId,
          "-Admin",
          $Source,
          "-CredentialRoot",
          $proofJson.credentialRoot,
          "-MetadataHash",
          $credentialRootMetadataHash,
          "-Network",
          $Network
        ) `
        $contracts `
        "add_credential_root" | Out-Null
    }

    Write-Step "registering Silent Witness proof on Stellar $Network"
    $runner = Join-Path $outDir "register-on-chain.ps1"
    $stdoutPath = Join-Path $outDir "stellar.stdout.log"
    $stderrPath = Join-Path $outDir "stellar.stderr.log"
    @"
`$ErrorActionPreference = "Stop"
Set-Location "$contracts"
& .\scripts\register-anonymous-verified.ps1 ``
  -ContractId "$ContractId" ``
  -Source "$Source" ``
  -VideoHash "$embeddedHash" ``
  -MetadataHash "$metadataHash" ``
  -ProofId "$proofId" ``
  -PublicInputsPath "$($proofJson.publicInputsPath)" ``
  -ProofPath "$($proofJson.proofPath)" ``
  -Network "$Network"
exit `$LASTEXITCODE
"@ | Set-Content -LiteralPath $runner -Encoding UTF8

    $process = Start-Process `
      -FilePath "powershell.exe" `
      -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runner) `
      -RedirectStandardOutput $stdoutPath `
      -RedirectStandardError $stderrPath `
      -WindowStyle Hidden `
      -PassThru
    if (!$process.WaitForExit($StellarTimeoutSeconds * 1000)) {
      $process.Kill()
      $partialOut = Get-Content -Raw -LiteralPath $stdoutPath -ErrorAction SilentlyContinue
      $partialErr = Get-Content -Raw -LiteralPath $stderrPath -ErrorAction SilentlyContinue
      throw "Stellar registration timed out after $StellarTimeoutSeconds seconds. stdout: $partialOut stderr: $partialErr"
    }

    $registerOutput = Get-Content -Raw -LiteralPath $stdoutPath -ErrorAction SilentlyContinue
    $registerError = Get-Content -Raw -LiteralPath $stderrPath -ErrorAction SilentlyContinue
    $exitCode = $process.ExitCode
    $looksSuccessful = $registerOutput -match '"video_hash"' -and $registerError -match 'Success'
    if (($null -ne $exitCode -and $exitCode -ne 0) -or (!$looksSuccessful -and $null -eq $exitCode)) {
      throw "Stellar registration failed with exit code $exitCode. stdout: $registerOutput stderr: $registerError"
    }
    $txStatus = "SUBMITTED"
    $txHash = (($registerError | Select-String -Pattern 'Signing transaction:\s+([0-9a-fA-F]{64})' | Select-Object -Last 1).Matches.Groups[1].Value)
    if (!$txHash) {
      $txHash = (($registerOutput | Select-String -Pattern '[0-9a-fA-F]{64}' | Select-Object -Last 1).Matches.Value)
    }
    $chainRecord = $registerOutput | ConvertFrom-Json
    if ($chainRecord.video_hash -ne $embeddedHash) {
      throw "Stellar contract returned a different video hash: $($chainRecord.video_hash)"
    }
  }

  Write-Step "persisting E2E registration event in NeonDB through backend"
  $registerBody = @{
    fileName = "embedded.mp4"
    videoHash = $embeddedHash
    metadataHash = $metadataHash
    proofId = $proofId
    tier = "silent"
    txHash = $txHash
    txStatus = $txStatus
    sourceAddress = $Source
    contractId = $ContractId
    silentWitness = @{
      credentialRoot = $proofJson.credentialRoot
      nullifier = $proofJson.nullifier
      proofBytes = $proofJson.proofBytes
      publicInputBytes = $proofJson.publicInputBytes
    }
    e2e = @{
      runId = $runId
      registerOnChain = [bool]$RegisterOnChain
    }
  } | ConvertTo-Json -Depth 10

  $registerEvent = Invoke-RestMethod `
    -Method Post `
    -Uri "$BackendUrl/api/proofs/register" `
    -Body $registerBody `
    -ContentType "application/json" `
    -TimeoutSec 30
  if (!$registerEvent.ok) {
    throw "backend register event did not return ok"
  }

  Write-Step "checking NeonDB lookup by embedded video hash"
  $lookup = Invoke-RestMethod -Method Get -Uri "$BackendUrl/api/proofs/by-video/$embeddedHash" -TimeoutSec 30
  if (($lookup.events | Measure-Object).Count -lt 1) {
    throw "NeonDB lookup returned no events for embedded video hash"
  }

  $summary = [ordered]@{
    ok = $true
    runId = $runId
    sourceHash = $sourceHash
    embeddedHash = $embeddedHash
    metadataHash = $metadataHash
    proofId = $proofId
    credentialRoot = $proofJson.credentialRoot
    nullifier = $proofJson.nullifier
    proofBytes = $proofJson.proofBytes
    publicInputBytes = $proofJson.publicInputBytes
    txStatus = $txStatus
    txHash = $txHash
    chainRecord = $chainRecord
    outputDir = $outDir
  }
  $summaryPath = Join-Path $outDir "summary.json"
  $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
  Write-Step "summary written to $summaryPath"
  $summary | ConvertTo-Json -Depth 10
}
catch {
  Write-Error $_
  exit 1
}
