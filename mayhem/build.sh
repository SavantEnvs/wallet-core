#!/usr/bin/env bash
#
# mayhem/build.sh — build wallet-core's upstream cargo-fuzz targets (one sanitized libFuzzer binary
# each, ASan via RUSTFLAGS) plus the KAT probe and the project's own test binaries for mayhem/test.sh.
#
# Upstream already ships cargo-fuzz crates next to the Rust crates they fuzz (rust/**/fuzz); each is
# its own workspace, so we build them as-is with `cargo fuzz build --fuzz-dir <crate>/fuzz` and
# copy the binaries to /mayhem/<name>. Names are unique (several crates call their target "sign").
#
# Not built: rust/chains/tw_internet_computer/fuzz (tw_internet_computer_transfer): its harness no
# longer compiles against the crate. Also upstream's tw_encoding base_encode/base_decode are stale too, so
# mayhem/fuzz carries corrected copies of those two.
#
# rustc ignores $SANITIZER_FLAGS (clang flags for C/C++); ASan comes from -Zsanitizer=address.
#
# DWARF gate (SPEC §6.2 item 10): cargo-fuzz's ASan build links rustc's precompiled DWARF5 asan
# runtime, which lands FIRST in .debug_info. $RUST_DEBUG_FLAGS therefore includes a -Clinker wrapper
# (built in mayhem/Dockerfile) that prepends a hand-built DWARF3 compile unit.
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs this script OFFLINE. The first (online)
# build populates $CARGO_HOME=/opt/toolchains/rust/cargo. Each fuzz crate's lockfile is committed as
# mayhem/locks/<crate>.Cargo.lock (upstream does not track them; they are not allowed outside
# mayhem/) and copied next to the manifest, so the offline re-run resolves the same versions from
# that cache. The runtime exports CARGO_NET_OFFLINE=true, so no `--offline` here.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

cd "$SRC"

TRIPLE="x86_64-unknown-linux-gnu"
# One target dir for all fuzz crates: the shared dependencies (tw_proto, tw_keypair, ...) compile once.
FUZZ_TARGET_DIR="$SRC/mayhem/fuzz-target"

# <fuzz crate dir, from the repo root>|<binary-name prefix>|<fuzz targets, space separated; * = all>
# Binary = /mayhem/<prefix><target>.
FUZZ_CRATES=(
  "rust/tw_evm/fuzz|evm_|*"
  "rust/tw_hash/fuzz||*"
  "rust/tw_cosmos_sdk/fuzz|cosmos_sdk_|*"
  # upstream's base_encode/base_decode no longer compile; mayhem/fuzz carries fixed copies
  "rust/tw_encoding/fuzz||cbor_encode_decode"
  "mayhem/fuzz||*"
  "rust/tw_keypair/fuzz||*"
  "rust/chains/tw_ton/fuzz|ton_|*"
  "rust/chains/tw_greenfield/fuzz|greenfield_|*"
  "rust/chains/tw_binance/fuzz|binance_|*"
  # upstream tw_aptos/fuzz has a broken tw_proto path; mayhem/fuzz-aptos is the same harness
  "mayhem/fuzz-aptos|aptos_|*"
  "rust/chains/tw_ripple/fuzz|ripple_|*"
  "rust/chains/tw_sui/fuzz|sui_|*"
  "rust/frameworks/tw_ton_sdk/fuzz|ton_sdk_|*"
)

: "${RUST_DEBUG_FLAGS:=-Cdebuginfo=2 -Zdwarf-version=3 -Clinker=/opt/mayhem-dwarf3-anchor/cc-wrapper.sh}"
mkdir -p "$FUZZ_TARGET_DIR"
# Leak detection off at build time (ASan stays on): the hook is linked into every fuzz binary.
clang -c -O1 -o "$FUZZ_TARGET_DIR/lsan_off.o" "$SRC/mayhem/lsan_off.c"
FUZZ_RUSTFLAGS="--cfg fuzzing -Zsanitizer=address -Cforce-frame-pointers -Clink-arg=$FUZZ_TARGET_DIR/lsan_off.o ${RUST_DEBUG_FLAGS}"

echo "=== cargo fuzz build (image nightly, ASan via RUSTFLAGS, DWARF3 anchor) ==="
echo "RUSTFLAGS=$FUZZ_RUSTFLAGS"

for entry in "${FUZZ_CRATES[@]}"; do
  IFS='|' read -r dir prefix targets <<<"$entry"
  name="$(basename "$(dirname "$dir")")"
  case "$dir" in mayhem/*) name="mayhem-$(basename "$dir")" ;; esac
  lock="mayhem/locks/$name.Cargo.lock"
  # Seed from the workspace lockfile on the very first (lock-generating) run; commit the result.
  if [ -f "$lock" ]; then cp "$lock" "$dir/Cargo.lock"; else cp rust/Cargo.lock "$dir/Cargo.lock"; fi
  if [ "$targets" = "*" ]; then
    targets=""; for f in "$dir"/fuzz_targets/*.rs; do targets="$targets $(basename "${f%.*}")"; done
  fi
  echo "--- building fuzz crate: $dir ($targets) ---"
  for t in $targets; do
    RUSTFLAGS="$FUZZ_RUSTFLAGS" cargo fuzz build --fuzz-dir "$dir" --target-dir "$FUZZ_TARGET_DIR" -O --debug-assertions "$t"
    bin="$FUZZ_TARGET_DIR/$TRIPLE/release/$t"
    [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
    cp "$bin" "/mayhem/${prefix}${t}"
    echo "built /mayhem/${prefix}${t}"
  done
done

# ── the project's own test binaries + the KAT probe, with NORMAL flags (no sanitizer; a functional
#    oracle, not a triage artifact). mayhem/test.sh only RUNS them. RUSTFLAGS must not leak in.
unset RUSTFLAGS
echo "=== precompiling the project's tests (normal flags) ==="
( cd rust && cargo test --no-run -p tw_hash -p tw_encoding -p tw_keypair -p tw_base58_address -p tw_bech32_address )

echo "=== building /mayhem/kat (KAT probe) ==="
[ -f mayhem/locks/kat.Cargo.lock ] && cp mayhem/locks/kat.Cargo.lock mayhem/kat/Cargo.lock || cp rust/Cargo.lock mayhem/kat/Cargo.lock
( cd mayhem/kat && cargo build --release )
cp mayhem/kat/target/release/kat /mayhem/kat

# LD_PRELOAD (the verify-repo sabotage check) can only neuter a dynamically linked executable.
if ! file /mayhem/kat | grep -q 'dynamically linked'; then
  echo "FATAL: /mayhem/kat is not dynamically linked — test.sh would be a reward-hackable oracle." >&2
  file /mayhem/kat >&2
  exit 1
fi

echo "build.sh complete"
