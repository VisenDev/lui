/* Process-local Objective-C ABI double; never link this into an application. */
#include <stdint.h>
#include <string.h>

typedef void *(*implementation)(void *, void *);
typedef int (*observer)(void);
static uintptr_t trace_count, placeholder_count = 1;
static int null_trace, retains, drains;
static observer inspect_modes;
static char names[64][128];
static unsigned name_count;

static void *intern(const char *name) {
    for (unsigned i = 0; i < name_count; ++i)
        if (!strcmp(names[i], name)) return names[i];
    if (name_count == 64 || strlen(name) >= sizeof names[0]) return 0;
    strcpy(names[name_count], name);
    return names[name_count++];
}
static void *original(void *self, void *selector) {
    (void)self; (void)selector;
    if (inspect_modes) inspect_modes();
    return null_trace ? 0 : &trace_count;
}
static implementation current = original;
void *objc_getClass(const char *name) { return intern(name); }
void *sel_registerName(const char *name) { return intern(name); }
void *class_getClassMethod(void *cls, const char *selector) {
    return !strcmp(cls, "NSThread") && !strcmp(selector, "callStackSymbols")
        ? &current : 0;
}
void *method_getImplementation(void *method) {
    return method == &current ? (void *)current : 0;
}
void *method_setImplementation(void *method, void *replacement) {
    if (method != &current) return 0;
    implementation old = current;
    current = (implementation)replacement;
    return (void *)old;
}
void *objc_msgSend(void *object, const char *selector, ...) {
    if (!strcmp(selector, "callStackSymbols"))
        return current(object, (void *)selector);
    if (!strcmp(selector, "count")) return (void *)*(uintptr_t *)object;
    if (!strcmp(selector, "stringWithUTF8String:")) return (void *)"trace";
    if (!strcmp(selector, "arrayWithObject:")) return &placeholder_count;
    if (!strcmp(selector, "retain")) ++retains;
    if (!strcmp(selector, "release")) --retains;
    if (!strcmp(selector, "drain")) ++drains;
    return object;
}
void test_trace(uintptr_t count, int is_null) {
    trace_count = count; null_trace = is_null;
}
void test_observer(void *function) { inspect_modes = (observer)function; }
void *test_original(void) { return &trace_count; }
int test_restored(void) { return current == original && retains == 0; }
int test_drains(void) { return drains; }
