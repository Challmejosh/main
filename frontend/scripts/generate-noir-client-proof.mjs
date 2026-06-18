import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { Noir } from '@noir-lang/noir_js'
import { UltraHonkBackend } from '@aztec/bb.js'

const BN254_FIELD_MODULUS =
  21888242871839275222246405745257275088548364400416034343698204186575808495617n

const args = parseArgs(process.argv.slice(2))
const videoHash = required(args.videoHash, '--videoHash')
const credentialSecret = required(args.credentialSecret, '--credentialSecret')
const nullifierSecret = required(args.nullifierSecret, '--nullifierSecret')
const outDir = args.outDir ?? '../zk/noir/silent_witness/target/e2e-client'

if (!/^[0-9a-fA-F]{64}$/.test(videoHash)) {
  throw new Error('--videoHash must be a 32-byte hex string')
}
for (const [name, value] of [
  ['--credentialSecret', credentialSecret],
  ['--nullifierSecret', nullifierSecret],
]) {
  if (!/^[0-9]+$/.test(value) || BigInt(value) <= 0n || BigInt(value) >= BN254_FIELD_MODULUS) {
    throw new Error(`${name} must be a decimal BN254 field element`)
  }
}

const helper = JSON.parse(
  await readFile('../zk/noir/silent_witness_helper/target/silent_witness_helper.json', 'utf8'),
)
const main = JSON.parse(
  await readFile('../zk/noir/silent_witness/target/silent_witness.json', 'utf8'),
)

const baseInputs = {
  credential_secret: credentialSecret,
  nullifier_secret: nullifierSecret,
  video_hash_hi: BigInt(`0x${videoHash.slice(0, 32)}`).toString(10),
  video_hash_lo: BigInt(`0x${videoHash.slice(32)}`).toString(10),
}

const helperResult = await new Noir(helper).execute(baseInputs)
const [credentialRoot, nullifier] = helperResult.returnValue
const mainInputs = {
  ...baseInputs,
  credential_root: credentialRoot,
  nullifier,
}

const { witness } = await new Noir(main).execute(mainInputs)
const backend = new UltraHonkBackend(main.bytecode)
try {
  const proofData = await backend.generateProof(witness, { keccak: true })
  const verified = await backend.verifyProof(proofData, { keccak: true })
  if (!verified) {
    throw new Error('generated proof failed local bb.js verification')
  }

  const publicInputs = proofData.publicInputs.map(fieldToBytes32).join('')
  await mkdir(outDir, { recursive: true })
  await writeFile(join(outDir, 'proof'), proofData.proof)
  await writeFile(join(outDir, 'public_inputs'), Buffer.from(publicInputs, 'hex'))
  await writeFile(
    join(outDir, 'proof.json'),
    JSON.stringify(
      {
        videoHash,
        credentialRoot: fieldToBytes32(credentialRoot),
        nullifier: fieldToBytes32(nullifier),
        proofPath: join(outDir, 'proof'),
        publicInputsPath: join(outDir, 'public_inputs'),
        proofBytes: proofData.proof.length,
        publicInputBytes: publicInputs.length / 2,
        verified,
      },
      null,
      2,
    ),
  )

  console.log(
    JSON.stringify({
      videoHash,
      credentialRoot: fieldToBytes32(credentialRoot),
      nullifier: fieldToBytes32(nullifier),
      proofPath: join(outDir, 'proof'),
      publicInputsPath: join(outDir, 'public_inputs'),
      proofBytes: proofData.proof.length,
      publicInputBytes: publicInputs.length / 2,
      verified,
    }),
  )
} finally {
  await backend.destroy()
}

function fieldToBytes32(value) {
  const normalized = value.startsWith('0x') ? value.slice(2) : BigInt(value).toString(16)
  if (normalized.length > 64) {
    throw new Error('field is larger than 32 bytes')
  }
  return normalized.padStart(64, '0')
}

function parseArgs(values) {
  const parsed = {}
  for (let index = 0; index < values.length; index += 1) {
    const current = values[index]
    if (!current.startsWith('--')) continue
    parsed[current.slice(2)] = values[index + 1]
    index += 1
  }
  return parsed
}

function required(value, name) {
  if (!value) {
    throw new Error(`${name} is required`)
  }
  return value
}
