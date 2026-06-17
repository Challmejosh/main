fn main(
    credential_secret: Field,
    nullifier_secret: Field,
    video_hash_hi: pub Field,
    video_hash_lo: pub Field,
    credential_root: pub Field,
    nullifier: pub Field,
) {
    let derived_root = std::hash::pedersen_hash([credential_secret]);
    let derived_nullifier = std::hash::pedersen_hash([
        credential_secret,
        nullifier_secret,
        video_hash_hi,
        video_hash_lo,
    ]);

    assert(derived_root == credential_root);
    assert(derived_nullifier == nullifier);
}
