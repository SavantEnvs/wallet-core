// Copy of rust/chains/tw_aptos/fuzz/fuzz_targets/sign.rs: upstream's fuzz/Cargo.toml points
// tw_proto at ../../tw_proto (one `..` short), so its crate cannot be built as-is.
#![no_main]

use libfuzzer_sys::fuzz_target;
use tw_aptos::signer::Signer;
use tw_proto::Aptos::Proto;

fuzz_target!(|input: Proto::SigningInput<'_>| {
    let _ = Signer::sign_proto(input);
});
