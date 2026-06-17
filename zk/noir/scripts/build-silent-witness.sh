#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../silent_witness"
nargo check
nargo execute witness
bb prove \
  --scheme ultra_honk \
  --oracle_hash keccak \
  --bytecode_path ./target/silent_witness.json \
  --witness_path ./target/witness.gz \
  --output_path ./target \
  --output_format bytes_and_fields

bb write_vk \
  --scheme ultra_honk \
  --oracle_hash keccak \
  --bytecode_path ./target/silent_witness.json \
  --output_path ./target \
  --output_format bytes_and_fields

if [[ -d target/vk_fields.json && -f target/vk_fields.json/vk_fields.json ]]; then
  mv target/vk_fields.json/vk_fields.json target/vk_fields.json.tmp
  rmdir target/vk_fields.json
  mv target/vk_fields.json.tmp target/vk_fields.json
fi

if [[ -d target/vk && -f target/vk/vk ]]; then
  mv target/vk/vk target/vk.tmp
  rmdir target/vk
  mv target/vk.tmp target/vk
fi

bb verify \
  --scheme ultra_honk \
  --oracle_hash keccak \
  --vk_path ./target/vk \
  --proof_path ./target/proof \
  --public_inputs_path ./target/public_inputs
