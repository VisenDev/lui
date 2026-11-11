#include <ecl/ecl.h>
#include <emscripten.h>

extern void init_lui_web(cl_object);

EMSCRIPTEN_KEEPALIVE
int lui_callback(int id, const char *arguments)
{
    cl_object function = ecl_read_from_cstring("LUI.WEB.FFI:DISPATCH");
    cl_object args = ecl_read_from_cstring(arguments);
    return cl_funcall(3, function, ecl_make_fixnum(id), args) != ECL_NIL;
}

EMSCRIPTEN_KEEPALIVE
void lui_release(int id)
{
    cl_funcall(2, ecl_read_from_cstring("LUI.WEB.FFI:RELEASE-ROOT"),
               ecl_make_fixnum(id));
}

int main(int argc, char **argv)
{
    cl_boot(argc, argv);
    ecl_init_module(NULL, init_lui_web);
    return 0; /* Emscripten keeps the runtime alive for browser callbacks. */
}
