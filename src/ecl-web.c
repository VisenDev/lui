#include <ecl/ecl.h>
#include <emscripten.h>
#include <math.h>

extern void init_lui_web(cl_object);

/* Separate argument frames permit synchronous, reentrant DOM callbacks. */
EM_JS(int, js_begin, (), { return LuiECL.frame([]); });
EM_JS(void, js_end, (int frame), { LuiECL.finish(frame); });
EM_JS(int, js_count, (int frame), { return LuiECL.frames.get(frame).length; });
EM_JS(int, js_execute, (int frame, int op), { return LuiECL.execute(frame, op); });
EM_JS(void, js_push, (int frame, int kind, double number, const void *data, int length), {
    let value;
    switch (kind) {
      case 0: value = null; break;
      case 1: value = undefined; break;
      case 2: value = false; break;
      case 3: value = true; break;
      case 4: value = number; break;
      case 5: case 6: {
        const view = kind === 5 ? HEAPU8.subarray(data, data + length)
                               : HEAPU32.subarray(data >>> 2, (data >>> 2) + length);
        const parts = [];
        for (let i = 0; i < length; i += 1024)
          parts.push(String.fromCodePoint(...view.subarray(i, i + 1024)));
        value = parts.join(""); break;
      }
      case 7: value = LuiECL.get(number); break;
      case 8: case 9: value = LuiECL.root(number, kind === 9); break;
    }
    LuiECL.frames.get(frame).push(value);
});
EM_JS(int, js_kind, (int frame, int index), {
    const value = LuiECL.frames.get(frame)[index];
    if (value === null) return 0;
    if (value === undefined) return 1;
    if (value === false) return 2;
    if (value === true) return 3;
    if (typeof value === 'number') return 4;
    if (typeof value === 'string') return 5;
    return LuiECL.rootIds.has(value) ? 8 : 7;
});
EM_JS(double, js_number, (int frame, int index), {
    return LuiECL.frames.get(frame)[index];
});
EM_JS(int, js_identity, (int frame, int index, int kind), {
    const value = LuiECL.frames.get(frame)[index];
    return kind === 8 ? LuiECL.rootIds.get(value) : LuiECL.retain(value);
});
EM_JS(int, js_string_length, (int frame, int index), {
    return Array.from(LuiECL.frames.get(frame)[index]).length;
});
EM_JS(void, js_string_copy, (int frame, int index, int *destination), {
    let offset = destination >>> 2;
    for (const character of LuiECL.frames.get(frame)[index])
      HEAPU32[offset++] = character.codePointAt(0);
});

static cl_object transport_id, reference_for, root_value, dispatch, release_root;
static cl_object constants[4];

static void initialize_bridge(void)
{
    if (transport_id) return;
    /* Interned symbols remain rooted by their packages. */
    cl_object package = ecl_find_package("LUI.WEB.FFI");
    transport_id = _ecl_intern("TRANSPORT-ID", package);
    reference_for = _ecl_intern("REFERENCE-FOR", package);
    root_value = _ecl_intern("ROOT-VALUE", package);
    dispatch = _ecl_intern("DISPATCH", package);
    release_root = _ecl_intern("RELEASE-ROOT", package);
    constants[0] = ecl_make_keyword("NULL");
    constants[1] = ecl_make_keyword("UNDEFINED");
    constants[2] = ecl_make_keyword("FALSE");
    constants[3] = ecl_make_keyword("TRUE");
}

static void push_value(int frame, cl_object value)
{
    if (value == ECL_NIL) { js_push(frame, 0, 0, NULL, 0); return; }
    for (int i = 0; i < 4; i++)
        if (value == constants[i]) { js_push(frame, i, 0, NULL, 0); return; }
    if (ECL_STRINGP(value)) {
        if (ECL_BASE_STRING_P(value))
            js_push(frame, 5, 0, value->base_string.self, ecl_length(value));
        else
            js_push(frame, 6, 0, value->string.self, ecl_length(value));
    } else if (ECL_REAL_TYPE_P(ecl_t_of(value))) {
        js_push(frame, 4, ecl_to_double(value), NULL, 0);
    } else {
        int id = ecl_to_int(cl_funcall(2, transport_id, value));
        js_push(frame, id >= 0 ? 7 : (cl_functionp(value) == ECL_NIL ? 8 : 9),
                id >= 0 ? id : -id, NULL, 0);
    }
}

static cl_object read_value(int frame, int index)
{
    int kind = js_kind(frame, index);
    if (kind < 4) return constants[kind];
    if (kind == 4) {
        double number = js_number(frame, index);
        if (number >= MOST_NEGATIVE_FIXNUM && number <= MOST_POSITIVE_FIXNUM &&
            floor(number) == number) return ecl_make_fixnum((cl_fixnum)number);
        return ecl_make_double_float(number);
    }
    if (kind == 5) {
        cl_object string = ecl_alloc_simple_extended_string(js_string_length(frame, index));
        js_string_copy(frame, index, string->string.self);
        return string;
    }
    int id = js_identity(frame, index, kind);
    return cl_funcall(2, kind == 8 ? root_value : reference_for, ecl_make_fixnum(id));
}

cl_object lui_js_operation(int op, cl_object arguments)
{
    initialize_bridge();
    int frame = js_begin();
    for (cl_object rest = arguments; rest != ECL_NIL; rest = ECL_CONS_CDR(rest))
        push_value(frame, ECL_CONS_CAR(rest));
    int failed = js_execute(frame, op);
    cl_object result = read_value(frame, 0);
    js_end(frame);
    if (failed) FEerror("Browser operation failed: ~A", 1, result);
    return result;
}

EMSCRIPTEN_KEEPALIVE
int lui_callback(int id, int frame)
{
    initialize_bridge();
    cl_object arguments = ECL_NIL;
    for (int i = js_count(frame) - 1; i >= 0; i--)
        arguments = ecl_cons(read_value(frame, i), arguments);
    return cl_funcall(3, dispatch, ecl_make_fixnum(id), arguments) != ECL_NIL;
}

EMSCRIPTEN_KEEPALIVE
void lui_release(int id)
{
    initialize_bridge();
    cl_funcall(2, release_root, ecl_make_fixnum(id));
}

int main(int argc, char **argv)
{
    cl_boot(argc, argv);
    ecl_init_module(NULL, init_lui_web);
    return 0; /* Emscripten keeps the runtime alive for browser callbacks. */
}
