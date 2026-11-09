// Known-answer probe for mayhem/test.sh: prints `KAT_<NAME>=<value>` lines that test.sh matches
// exactly. Expected values are published test vectors (FIPS 180, Keccak, RFC 8032, secp256k1 G).
use tw_encoding::{base58, hex};
use tw_hash::{sha2, sha3};
use tw_keypair::tw::{Curve, PrivateKey, PublicKeyType};

fn main() {
    println!("KAT_SHA256={}", hex::encode(sha2::sha256(b"abc"), false));
    println!("KAT_KECCAK256={}", hex::encode(sha3::keccak256(b""), false));
    println!(
        "KAT_BASE58={}",
        base58::encode(b"Hello World!", base58::Alphabet::Bitcoin)
    );

    // secp256k1: private key 1 -> the generator point G (compressed).
    let mut one = vec![0u8; 32];
    one[31] = 1;
    let private = PrivateKey::new(one).expect("secp256k1 key");
    let public = private
        .get_public_key_by_type(PublicKeyType::Secp256k1)
        .expect("secp256k1 public key");
    println!("KAT_SECP256K1_PUB={}", hex::encode(public.to_bytes(), false));
    let digest = sha2::sha256(b"abc");
    let sig = private.sign(&digest, Curve::Secp256k1).expect("secp256k1 sign");
    println!("KAT_SECP256K1_VERIFY={}", public.verify(&sig, &digest));

    // RFC 8032 section 7.1, test 1 (empty message).
    let seed = hex::decode("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
        .expect("seed hex");
    let ed = PrivateKey::new(seed).expect("ed25519 key");
    let ed_pub = ed
        .get_public_key_by_type(PublicKeyType::Ed25519)
        .expect("ed25519 public key");
    println!("KAT_ED25519_PUB={}", hex::encode(ed_pub.to_bytes(), false));
    let ed_sig = ed.sign(b"", Curve::Ed25519).expect("ed25519 sign");
    println!("KAT_ED25519_SIG={}", hex::encode(ed_sig, false));
}
