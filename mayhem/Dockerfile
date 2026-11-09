# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile for wallet-core (Trust Wallet core; the Rust workspace under rust/).
# Builds ON TOP of the org base image, adding the pinned Rust nightly upstream itself uses
# (tools/install-rust-dependencies) + cargo-fuzz under /opt/toolchains/rust (SPEC §6.2 item 8),
# plus a DWARF3 "anchor" object so the first compile unit of every fuzz binary is DWARF 3
# (SPEC §6.2 item 10; see mayhem/build.sh).
#
# Build (from the repo root, on the `mayhem` branch):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) -t wallet-core-commit:test .

FROM ghcr.io/savantenvs/base:20261023

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (never an ENV — an empty ENV breaks clang). build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH
# Undefaulted (no '=') so the base ENV default flows through unless --build-arg overrides it.
ARG SANITIZER_FLAGS

# Same nightly as upstream's tools/install-rust-dependencies (-Zsanitizer=address needs nightly).
ARG RUST_CHANNEL=nightly-2025-12-11
ARG CARGO_FUZZ_VERSION=0.13.1

ENV RUSTUP_HOME=/opt/toolchains/rust/rustup \
    CARGO_HOME=/opt/toolchains/rust/cargo \
    PATH=/opt/toolchains/rust/cargo/bin:${PATH}

USER root
RUN install -d /opt/toolchains/rust \
 && curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs -o /tmp/rustup-init.sh \
 && sh /tmp/rustup-init.sh -y --no-modify-path --profile minimal \
        --default-toolchain "${RUST_CHANNEL}" \
 && rustup component add rust-src --toolchain "${RUST_CHANNEL}" \
 && cargo install cargo-fuzz --version "${CARGO_FUZZ_VERSION}" --locked \
 && rm -f /tmp/rustup-init.sh \
 # The commit build AND the air-gapped PATCH re-run run as `mayhem` (2000): it must read the
 # toolchain and read/refresh the cargo registry cache.
 && chown -R 2000:2000 /opt/toolchains/rust

# DWARF<4 anchor (SPEC §6.2 item 10): cargo-fuzz's ASan build links rustc's precompiled
# DWARF5 asan runtime first, so rustc's own debuginfo flags cannot make the FIRST compile unit
# DWARF3. A `-Clinker` wrapper prepends a tiny hand-built DWARF3 object.
RUN install -d /opt/mayhem-dwarf3-anchor \
 && printf 'const int mayhem_dwarf3_anchor = 0;\n' > /opt/mayhem-dwarf3-anchor/anchor.c \
 && clang -g -gdwarf-3 -c /opt/mayhem-dwarf3-anchor/anchor.c -o /opt/mayhem-dwarf3-anchor/anchor.o \
 && printf '#!/bin/sh\nexec clang /opt/mayhem-dwarf3-anchor/anchor.o "$@"\n' \
        > /opt/mayhem-dwarf3-anchor/cc-wrapper.sh \
 && chmod +x /opt/mayhem-dwarf3-anchor/cc-wrapper.sh \
 && chmod -R a+rX /opt/mayhem-dwarf3-anchor

# Source enters from the build CONTEXT (CI checkout): the FULL repo (incl. .git) → /mayhem.
USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# Populates $CARGO_HOME (online, this first build) and builds the sanitized fuzz targets + KAT probe.
RUN bash mayhem/build.sh

# Run the project's functional suite at build time IF present (a failing suite fails the build).
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
