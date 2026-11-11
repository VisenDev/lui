#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
case ${1:-gallery} in
    gallery) build_directory=build/web-ecl; html=build/web-ecl/index.html; title='LUI — ECL / WebAssembly' ;;
    docs) build_directory=build/docs-ecl; html=build/docs.html; title='LUI documentation' ;;
    *) echo 'Usage: build-web-ecl.sh [gallery|docs]' >&2; exit 2 ;;
esac
export ECL_WEB_KIND=${1:-gallery}
: "${ECL:=ecl}"
: "${EMCC:=emcc}"
: "${ECL_WASM:=$PWD/build/deps/ecl-wasm}"
if [[ -n ${EMSDK_ENV:-} ]]; then
    if [[ ! -f $EMSDK_ENV ]]; then
        echo "Emscripten environment script not found: $EMSDK_ENV" >&2
        exit 2
    fi
    source "$EMSDK_ENV"
elif [[ $EMCC == emcc ]] && ! command -v "$EMCC" >/dev/null 2>&1 \
        && [[ -f build/deps/emsdk/emsdk_env.sh ]]; then
    source build/deps/emsdk/emsdk_env.sh
fi
for compiler in "$ECL" "$EMCC"; do
    if ! command -v "$compiler" >/dev/null 2>&1; then
        echo "Required compiler not found: $compiler" >&2
        echo 'Set ECL/EMCC explicitly, or set EMSDK_ENV to your SDK emsdk_env.sh.' >&2
        exit 2
    fi
done
if [[ ! -d $ECL_WASM ]]; then
    echo "ECL WebAssembly runtime not found: $ECL_WASM" >&2
    echo 'Run make web-ecl-toolchain or set ECL_WASM to an installed runtime.' >&2
    exit 2
fi
ECL_WASM=$(cd "$ECL_WASM" && pwd)
if [[ -z ${ECL_TARGET_INFO:-} ]]; then
    shopt -s nullglob
    targets=("$ECL_WASM"/target-info.lsp "$ECL_WASM"/lib/ecl-*/target-info.lsp)
    [[ -f ${targets[0]} ]] || targets=("${targets[@]:1}")
    if [[ ${#targets[@]} != 1 ]]; then
        echo 'Set ECL_TARGET_INFO to the matching wasm target-info.lsp.' >&2
        exit 2
    fi
    ECL_TARGET_INFO=${targets[0]}
fi
export ECL_TARGET_INFO
if [[ -f $ECL_WASM/libecl.a ]]; then
    include=$ECL_WASM
    libraries=$ECL_WASM
else
    include=$ECL_WASM/include
    libraries=$ECL_WASM/lib
fi
"$ECL" -norc -shell scripts/build-web-ecl.lisp
"$EMCC" -O0 -I"$include" src/ecl-web.c \
    "$build_directory/liblui-web.a" "$libraries"/libecl.a \
    "$libraries"/libeclgc.a "$libraries"/libeclgmp.a \
    -lm -sSTACK_SIZE=4194304 -sALLOW_MEMORY_GROWTH=1 \
    -sBINARYEN_EXTRA_PASSES=--spill-pointers -sEXIT_RUNTIME=0 -sSINGLE_FILE=1 \
    -sEXPORTED_FUNCTIONS='["_main","_lui_callback","_lui_release","_malloc","_free"]' \
    --pre-js src/ecl-web.js -o "$build_directory/lui.js"
rm -f "$build_directory/lui.wasm"
"${PYTHON:-python3}" scripts/package-web-ecl.py \
    --javascript "$build_directory/lui.js" --output "$html" --title "$title"
