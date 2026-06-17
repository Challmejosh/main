#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 3 || "$#" -gt 4 ]]; then
  echo "usage: $0 <video-hash-hex> <credential-secret-field> <nullifier-secret-field> [output-dir]" >&2
  exit 2
fi

VIDEO_HASH="$1"
CREDENTIAL_SECRET="$2"
NULLIFIER_SECRET="$3"
OUTPUT_DIR="${4:-}"

if [[ ! "$VIDEO_HASH" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "video hash must be a 32-byte hex string" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER_DIR="$ROOT_DIR/silent_witness_helper"
CIRCUIT_DIR="$ROOT_DIR/silent_witness"
HELPER_TOML="$HELPER_DIR/Prover.toml"
CIRCUIT_TOML="$CIRCUIT_DIR/Prover.toml"
HELPER_BACKUP="$HELPER_DIR/Prover.toml.harpocrates.bak"
CIRCUIT_BACKUP="$CIRCUIT_DIR/Prover.toml.harpocrates.bak"

HI_HEX="${VIDEO_HASH:0:32}"
LO_HEX="${VIDEO_HASH:32:32}"
HI_DEC="$(python3 - "$HI_HEX" <<'PY'
import sys
print(int(sys.argv[1], 16))
PY
)"
LO_DEC="$(python3 - "$LO_HEX" <<'PY'
import sys
print(int(sys.argv[1], 16))
PY
)"

cleanup() {
  if [[ -f "$HELPER_BACKUP" ]]; then
    mv "$HELPER_BACKUP" "$HELPER_TOML"
  fi
  if [[ -f "$CIRCUIT_BACKUP" ]]; then
    mv "$CIRCUIT_BACKUP" "$CIRCUIT_TOML"
  fi
}
trap cleanup EXIT

cp "$HELPER_TOML" "$HELPER_BACKUP"
cp "$CIRCUIT_TOML" "$CIRCUIT_BACKUP"

cat > "$HELPER_TOML" <<EOF
credential_secret = "$CREDENTIAL_SECRET"
nullifier_secret = "$NULLIFIER_SECRET"
video_hash_hi = "$HI_DEC"
video_hash_lo = "$LO_DEC"
EOF

pushd "$HELPER_DIR" >/dev/null
HELPER_OUTPUT="$(nargo execute generated_helper)"
popd >/dev/null

ROOT_AND_NULLIFIER="$(HELPER_OUTPUT="$HELPER_OUTPUT" python3 -c 'import os, re; mod = 21888242871839275222246405745257275088548364400416034343698204186575808495617; values = [int(match) % mod for match in re.findall(r"Field\((-?\d+)\)", os.environ["HELPER_OUTPUT"])]; assert len(values) == 2, values; print(" ".join(f"0x{value:064x}" for value in values))')"
read -r CREDENTIAL_ROOT NULLIFIER <<< "$ROOT_AND_NULLIFIER"

cat > "$CIRCUIT_TOML" <<EOF
credential_secret = "$CREDENTIAL_SECRET"
nullifier_secret = "$NULLIFIER_SECRET"
video_hash_hi = "$HI_DEC"
video_hash_lo = "$LO_DEC"
credential_root = "$CREDENTIAL_ROOT"
nullifier = "$NULLIFIER"
EOF

pushd "$CIRCUIT_DIR" >/dev/null
nargo check >/dev/null
nargo execute witness >/dev/null
bb prove \
  --scheme ultra_honk \
  --oracle_hash keccak \
  --bytecode_path ./target/silent_witness.json \
  --witness_path ./target/witness.gz \
  --output_path ./target \
  --output_format bytes_and_fields >/dev/null
bb verify \
  --scheme ultra_honk \
  --oracle_hash keccak \
  --vk_path ./target/vk \
  --proof_path ./target/proof \
  --public_inputs_path ./target/public_inputs >/dev/null
popd >/dev/null

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$CIRCUIT_DIR/target/generated/$VIDEO_HASH"
fi
mkdir -p "$OUTPUT_DIR"
cp "$CIRCUIT_DIR/target/proof" "$OUTPUT_DIR/proof"
cp "$CIRCUIT_DIR/target/public_inputs" "$OUTPUT_DIR/public_inputs"

python3 - "$VIDEO_HASH" "$CREDENTIAL_ROOT" "$NULLIFIER" "$OUTPUT_DIR" <<'PY'
import json
import pathlib
import sys

video_hash, credential_root, nullifier, output_dir = sys.argv[1:5]
output = pathlib.Path(output_dir)
proof = output.joinpath("proof").read_bytes()
public_inputs = output.joinpath("public_inputs").read_bytes()

print(json.dumps({
    "videoHash": video_hash.lower(),
    "credentialRoot": credential_root.removeprefix("0x"),
    "nullifier": nullifier.removeprefix("0x"),
    "proof": proof.hex(),
    "publicInputs": public_inputs.hex(),
    "proofBytes": len(proof),
    "publicInputBytes": len(public_inputs),
    "proofPath": str(output.joinpath("proof")),
    "publicInputsPath": str(output.joinpath("public_inputs")),
}))
PY
