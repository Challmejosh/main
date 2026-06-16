# Harpocrates Soroban Contracts

This workspace contains the Stellar Soroban contracts for Harpocrates.

## Contracts

```text
contracts/harpocrates-registry
```

`HarpocratesRegistry` stores evidence records for all identity tiers:

- Tier 1 Silent Witness: anonymous Noir proof with nullifier protection.
- Tier 2 Consistent Source: Stellar account signed source.
- Tier 3 Public Seal: approved institutional issuer.

## Build

```powershell
cargo test
stellar contract build
```

The current registry exports:

```text
init
add_credential_root
revoke_credential_root
get_credential_root
add_issuer
revoke_issuer
set_verifier
get_verifier
register_anonymous
register_anonymous_verified
register_source
register_seal
revoke_proof
get_proof
get_by_video
has_nullifier
get_issuer
```

## Tier 1 Verifier

`register_anonymous` is the development/demo boundary.

`register_anonymous_verified` is the real Tier 1 entrypoint. It checks public
inputs, requires an active credential root, prevents nullifier reuse, then calls
the configured verifier contract:

```text
verify_proof(public_inputs, proof)
```

See `VERIFIER_INTEGRATION.md` for the UltraHonk verifier deployment plan.

Current Testnet verifier:

```text
CCP2EQPKT5XAYTOARX3LGHNMJ37A6W2WY3H54MRIHEZVTVAZZPUSGZQJ
```

## Events

The registry emits typed Soroban events with `#[contractevent]`:

```text
["proof", "reg", proof_id]        => video_hash, tier, status
["proof", "revoke", proof_id]     => status
["issuer", "add", issuer]         => metadata_hash
["issuer", "revoke", issuer]      => {}
["verif", "set", verifier]        => {}
["credroot", "add", root]         => metadata_hash, issued_at
["credroot", "revoke", root]      => {}
```

## Scripts

PowerShell helpers live in `scripts/`:

```text
add-issuer.ps1
add-credential-root.ps1
register-anonymous-verified.ps1
register-source.ps1
register-seal.ps1
revoke-credential-root.ps1
set-verifier.ps1
```
