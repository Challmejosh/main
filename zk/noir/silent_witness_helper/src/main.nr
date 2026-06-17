fn main(
    credential_secret: Field,
    nullifier_secret: Field,
    video_hash_hi: Field,
    video_hash_lo: Field,
) -> pub (Field, Field) {
    let credential_root = std::hash::pedersen_hash([credential_secret]);
    let nullifier = std::hash::pedersen_hash([
        credential_secret,
        nullifier_secret,
        video_hash_hi,
        video_hash_lo,
    ]);

    (credential_root, nullifier)
}
