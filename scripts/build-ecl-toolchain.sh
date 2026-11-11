#!/usr/bin/env bash
# ECL's source tree is read-only; both configurations live in build/deps/.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ECL_SOURCE:?Set ECL_SOURCE to an ECL checkout with cross-compilation support}"
: "${EMSDK_ENV:?Set EMSDK_ENV to the installed SDK emsdk_env.sh}"
: "${JOBS:=4}"
ECL_SOURCE=$(cd "$ECL_SOURCE" && pwd)
source "$EMSDK_ENV"
deps=$PWD/build/deps
mkdir -p "$deps/ecl-host-build" "$deps/ecl-wasm-build"
(
    cd "$deps/ecl-host-build"
    "$ECL_SOURCE/src/configure" --prefix="$deps/ecl-host" \
        --disable-shared --disable-threads
    make -j"$JOBS"
    make install
)
export ECL_TO_RUN=$deps/ecl-host/bin/ecl
(
    cd "$deps/ecl-wasm-build"
    emconfigure "$ECL_SOURCE/src/configure" \
        --host=wasm32-unknown-emscripten \
        --build="$("$ECL_SOURCE/src/gmp/config.guess")" \
        --with-cross-config="$ECL_SOURCE/src/util/wasm32-unknown-emscripten.cross_config" \
        --prefix="$deps/ecl-wasm" --disable-shared --with-tcp=no --with-cmp=no
    emmake make -j"$JOBS"
    # ECL's Emscripten install is flat; some revisions leave bindir empty.
    emmake make install bindir="$deps/ecl-wasm"
)
