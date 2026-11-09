#!/usr/bin/env bash
#
# wallet-core/mayhem/test.sh — RUN the Rust crates' own test suites plus a known-answer probe and
# emit a CTRF summary. Exit 0 iff nothing failed. build.sh did the building; this only runs.
#
#  1) `cargo test` for the crypto/encoding crates build.sh precompiled (hash, encoding, keypair,
#     base58/bech32 addresses): published test vectors asserted with assert_eq!.
#  2) The KAT probe /mayhem/kat — the load-bearing part. It is a dynamically linked plain binary
#     (the verify-repo sabotage check can LD_PRELOAD-neuter it) printing SHA-256, Keccak-256, Base58,
#     secp256k1 and Ed25519 results for fixed inputs; every line is matched exactly below.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

PASSED=0; FAILED=0; SKIPPED=0

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not available — cannot run the test suite" >&2
  emit_ctrf "cargo-test+kat" 0 1 0; exit 2
fi

echo "=== running: cargo test (hash, encoding, keypair, base58/bech32 addresses) ==="
OUT="$SRC/mayhem-build-test.log"
( cd rust && cargo test -p tw_hash -p tw_encoding -p tw_keypair -p tw_base58_address -p tw_bech32_address 2>&1 ) | tee "$OUT"
rc=${PIPESTATUS[0]}

# libtest summary: "test result: ok. 112 passed; 0 failed; 3 ignored; ..."; sum over all binaries.
while read -r p f s; do
  PASSED=$(( PASSED + p )); FAILED=$(( FAILED + f )); SKIPPED=$(( SKIPPED + s ))
done < <(grep -oE '[0-9]+ passed; [0-9]+ failed; [0-9]+ ignored' "$OUT" \
          | sed -E 's/([0-9]+) passed; ([0-9]+) failed; ([0-9]+) ignored/\1 \2 \3/')

if [ "$(( PASSED + FAILED + SKIPPED ))" -eq 0 ]; then
  echo "FAIL: no test-result summary parsed — the suite did not run (cargo exit $rc)" >&2
  emit_ctrf "cargo-test+kat" 0 1 0; exit 1
fi
# A non-zero cargo exit with zero counted failures is a build/harness error.
if [ "$rc" -ne 0 ] && [ "$FAILED" -eq 0 ]; then FAILED=$(( FAILED + 1 )); fi

# UNCONDITIONAL: a missing probe is a failure, never a skip.
echo "=== KAT probe: /mayhem/kat ==="
KAT_OUT="$(/mayhem/kat 2>&1)"; kat_rc=$?
echo "$KAT_OUT"

kat_expect() {
  local label="$1" line="$2"
  if printf '%s\n' "$KAT_OUT" | grep -qxF "$line"; then
    echo "KAT PASS: $label"
    PASSED=$(( PASSED + 1 ))
  else
    echo "KAT FAIL: $label — expected exact line: $line" >&2
    FAILED=$(( FAILED + 1 ))
  fi
}

if [ "$kat_rc" -ne 0 ]; then
  echo "KAT FAIL: /mayhem/kat exited $kat_rc (neutered, missing, or broken)" >&2
  FAILED=$(( FAILED + 1 ))
fi
# Published vectors: FIPS 180 SHA-256("abc"); Keccak-256(""); Base58("Hello World!");
# secp256k1 pubkey of private key 1 = generator G, and a verifying signature; RFC 8032 §7.1 test 1.
kat_expect "SHA-256 (abc)"        'KAT_SHA256=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
kat_expect "Keccak-256 (empty)"   'KAT_KECCAK256=c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470'
kat_expect "Base58 (Hello World!)" 'KAT_BASE58=2NEpo7TZRRrLZSi2U'
kat_expect "secp256k1 public key (G)" 'KAT_SECP256K1_PUB=0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798'
kat_expect "secp256k1 sign+verify" 'KAT_SECP256K1_VERIFY=true'
kat_expect "Ed25519 public key (RFC 8032)" 'KAT_ED25519_PUB=d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'
kat_expect "Ed25519 signature (RFC 8032)" 'KAT_ED25519_SIG=e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b'

emit_ctrf "cargo-test+kat" "$PASSED" "$FAILED" "$SKIPPED"
