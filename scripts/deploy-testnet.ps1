param(
  [string] $Admin = "harpocrates-admin",
  [string] $Issuer = "harpocrates-issuer",
  [string] $Network = "testnet",
  [string] $Verifier = "CCP2EQPKT5XAYTOARX3LGHNMJ37A6W2WY3H54MRIHEZVTVAZZPUSGZQJ",
  [string] $RpcUrl = "https://soroban-testnet.stellar.org",
  [switch] $SkipBuild,
  [switch] $SkipIssuer,
  [switch] $SkipE2E,
  [int] $StellarTimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$contracts = Join-Path $root "contracts"
$frontendEnv = Join-Path $root "frontend\.env.local"
$deployId = [Guid]::NewGuid().ToString("N")
$outDir = Join-Path $root "tmp\deploy-$deployId"
New-Item -ItemType Directory -Force $outDir | Out-Null

function Write-Step($message) {
  Write-Host "[harpocrates-deploy] $message"
}

function Invoke-External($description, $filePath, [string[]] $arguments, $workingDirectory) {
  Write-Step $description
  $stdoutPath = Join-Path $outDir ([Guid]::NewGuid().ToString("N") + ".stdout.log")
  $stderrPath = Join-Path $outDir ([Guid]::NewGuid().ToString("N") + ".stderr.log")
  $process = Start-Process `
    -FilePath $filePath `
    -ArgumentList $arguments `
    -WorkingDirectory $workingDirectory `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath `
    -WindowStyle Hidden `
    -Wait `
    -PassThru

  $stdout = Get-Content -LiteralPath $stdoutPath -ErrorAction SilentlyContinue
  $stderr = Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue
  $stdout | ForEach-Object { Write-Host $_ }
  $stderr | ForEach-Object { Write-Host $_ }

  if ($process.ExitCode -ne 0) {
    throw "$description failed with exit code $($process.ExitCode)"
  }
  return @($stdout + $stderr)
}

function Invoke-DeployScript($description, $scriptPath, [string[]] $arguments, $workingDirectory) {
  $scriptArguments = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $scriptPath
  ) + $arguments
  return Invoke-External $description "powershell.exe" $scriptArguments $workingDirectory
}

function Get-Sha256String($value) {
  $bytes = [Text.Encoding]::UTF8.GetBytes($value)
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($bytes)
    return ([BitConverter]::ToString($hash) -replace "-", "").ToLowerInvariant()
  }
  finally {
    $sha.Dispose()
  }
}

function Get-FirstContractId($output) {
  $joined = ($output -join "`n")
  $match = [regex]::Match($joined, "C[A-Z0-9]{55}")
  if (!$match.Success) {
    throw "could not find a contract id in deploy output"
  }
  return $match.Value
}

function Set-EnvValue($path, $name, $value) {
  $lines = @()
  if (Test-Path $path) {
    $lines = @(Get-Content -LiteralPath $path)
  }

  $found = $false
  $next = foreach ($line in $lines) {
    if ($line -match "^$([regex]::Escape($name))=") {
      $found = $true
      "$name=$value"
    }
    else {
      $line
    }
  }

  if (!$found) {
    $next += "$name=$value"
  }

  $next | Set-Content -LiteralPath $path -Encoding UTF8
}

try {
  $adminAddress = (stellar keys address $Admin).Trim()
  $issuerAddress = (stellar keys address $Issuer).Trim()

  if (!$SkipBuild) {
    Invoke-External "running Soroban contract tests" "cargo" @("test") $contracts | Out-Null
    Invoke-External "building registry WASM" "stellar" @("contract", "build") $contracts | Out-Null
  }

  $deployOutput = Invoke-External "deploying HarpocratesRegistry to $Network" "stellar" @(
    "contract",
    "deploy",
    "--wasm",
    "target\wasm32v1-none\release\harpocrates_registry.wasm",
    "--source",
    $Admin,
    "--network",
    $Network
  ) $contracts
    $contractId = Get-FirstContractId $deployOutput

  Invoke-External "initializing registry admin" "stellar" @(
    "contract",
    "invoke",
    "--id",
    $contractId,
    "--source",
    $Admin,
    "--network",
    $Network,
    "--",
    "init",
    "--admin",
    $Admin
  ) $contracts | Out-Null

    Invoke-DeployScript "attaching Silent Witness verifier" (Join-Path $contracts "scripts\set-verifier.ps1") @(
      "-ContractId",
      $contractId,
      "-Admin",
      $Admin,
      "-Verifier",
      $Verifier,
      "-Network",
      $Network
    ) $contracts | Out-Null

    if (!$SkipIssuer) {
      $issuerMetadataHash = Get-Sha256String "harpocrates:issuer:$issuerAddress"
      Invoke-DeployScript "adding public seal issuer" (Join-Path $contracts "scripts\add-issuer.ps1") @(
        "-ContractId",
        $contractId,
        "-Admin",
        $Admin,
        "-Issuer",
        $Issuer,
        "-MetadataHash",
        $issuerMetadataHash,
        "-Network",
        $Network
      ) $contracts | Out-Null
    }

  Write-Step "updating frontend environment"
  Set-EnvValue $frontendEnv "VITE_API_BASE" "http://127.0.0.1:5050"
  Set-EnvValue $frontendEnv "VITE_STELLAR_RPC_URL" $RpcUrl
  Set-EnvValue $frontendEnv "VITE_STELLAR_READONLY_SOURCE" $adminAddress
  Set-EnvValue $frontendEnv "VITE_HARPOCRATES_REGISTRY_ID" $contractId

  $e2eSummary = $null
  if (!$SkipE2E) {
    Write-Step "running on-chain E2E smoke test"
    $e2eOutput = & (Join-Path $PSScriptRoot "e2e-harpocrates.ps1") `
      -ContractId $contractId `
      -Source $Admin `
      -Network $Network `
      -RegisterOnChain `
      -EnsureCredentialRoot `
      -StellarTimeoutSeconds $StellarTimeoutSeconds
    if ($LASTEXITCODE -ne 0) {
      throw "E2E smoke test failed"
    }
    $e2eOutput | ForEach-Object { Write-Host $_ }
    $e2eMatch = [regex]::Match(($e2eOutput -join "`n"), "summary written to (.+?summary\.json)")
    $e2eSummaryPath = if ($e2eMatch.Success) { $e2eMatch.Groups[1].Value.Trim() } else { $null }
    if (!$e2eSummaryPath) {
      $latestE2eSummary = Get-ChildItem -Path (Join-Path $root "tmp") -Recurse -Filter "summary.json" |
        Where-Object { $_.FullName -match "\\e2e-" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
      $e2eSummaryPath = $latestE2eSummary.FullName
    }
    if (!$e2eSummaryPath -or !(Test-Path $e2eSummaryPath)) {
      throw "could not locate E2E summary file"
    }
    $e2eSummary = Get-Content -Raw -LiteralPath $e2eSummaryPath | ConvertFrom-Json
  }

  $summary = [ordered]@{
    ok = $true
    deployId = $deployId
    network = $Network
    contractId = $contractId
    verifier = $Verifier
    admin = $adminAddress
    issuer = if ($SkipIssuer) { $null } else { $issuerAddress }
    frontendEnv = $frontendEnv
    e2e = $e2eSummary
    outputDir = $outDir
  }
  $summaryPath = Join-Path $outDir "summary.json"
  $summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
  Write-Step "summary written to $summaryPath"
  $summary | ConvertTo-Json -Depth 20
}
catch {
  Write-Error $_
  exit 1
}
