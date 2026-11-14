#!/usr/bin/env bash
# Download pinned tools when no overrides are supplied; install locally.
set -euo pipefail
cd "$(dirname "$0")/.."
deps=$PWD/build/deps
for tool in git make python3 cc c++; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Missing build prerequisite: $tool" >&2
        exit 2
    fi
done

# Never update or switch an existing checkout. Explicit overrides remain owned
# by the caller; fresh default checkouts use the revisions tested with LUI.
checkout() {
    local destination=$1 repository=$2 revision=$3
    if [[ ! -d $destination ]]; then
        mkdir -p "$destination"
        git -C "$destination" init
        git -C "$destination" remote add origin "$repository"
    elif [[ ! -d $destination/.git ]]; then
        echo "Expected a Git checkout at $destination; set an explicit tool override." >&2
        exit 2
    fi
    # Retry an interrupted initial download on the next setup invocation.
    if ! git -C "$destination" rev-parse --verify HEAD >/dev/null 2>&1; then
        git -C "$destination" fetch --depth 1 origin "$revision"
        git -C "$destination" checkout --detach FETCH_HEAD
    fi
}

if [[ -z ${ECL_SOURCE:-} ]]; then
    ECL_SOURCE=$deps/ecl-source
    checkout "$ECL_SOURCE" https://gitlab.com/embeddable-common-lisp/ecl.git \
        855f93431bab0e972fad816a8e0437afdc1de245
fi
if [[ -z ${EMSDK_ENV:-} ]]; then
    checkout "$deps/emsdk" https://github.com/emscripten-core/emsdk.git \
        1693ce7359fc9694f198694f902a2cc061239b86
    "$deps/emsdk/emsdk" install 4.0.12
    "$deps/emsdk/emsdk" activate 4.0.12
    EMSDK_ENV=$deps/emsdk/emsdk_env.sh
fi
: "${JOBS:=4}"
ECL_SOURCE=$(cd "$ECL_SOURCE" && pwd)
source "$EMSDK_ENV"
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
