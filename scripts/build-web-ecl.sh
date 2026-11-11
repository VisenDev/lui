#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ECL:=ecl}"
: "${EMCC:=emcc}"
: "${ECL_WASM:=$PWD/build/deps/ecl-wasm}"
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
command -v "$ECL" >/dev/null
command -v "$EMCC" >/dev/null
"$ECL" -norc -shell scripts/build-web-ecl.lisp
"$EMCC" -O0 -I"$include" src/ecl-web.c \
    build/web-ecl/liblui-web.a "$libraries"/libecl.a \
    "$libraries"/libeclgc.a "$libraries"/libeclgmp.a \
    -lm -sSTACK_SIZE=4194304 -sALLOW_MEMORY_GROWTH=1 \
    -sBINARYEN_EXTRA_PASSES=--spill-pointers -sEXIT_RUNTIME=0 \
    -sEXPORTED_RUNTIME_METHODS='["stringToNewUTF8"]' \
    -sEXPORTED_FUNCTIONS='["_main","_lui_callback","_lui_release","_malloc","_free"]' \
    --pre-js src/ecl-web.js -o build/web-ecl/lui.js
sed 's#../build/web-ecl/lui.js#lui.js#g' \
    examples/web-ecl.html > build/web-ecl/index.html
