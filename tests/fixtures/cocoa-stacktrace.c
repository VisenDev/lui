/* Process-local Objective-C ABI double; never link this into an application. */
#include <stdint.h>
#include <string.h>

typedef void *(*implementation)(void *, void *);
typedef int (*observer)(void);
static uintptr_t trace_count, placeholder_count = 1;
static int null_trace, retains, drains;
static observer inspect_modes;
static char names[64][128];
static unsigned name_count, selector_calls;
struct test_path { int references; };
static struct test_path paths[2048];
static unsigned path_count, path_retains, path_releases, fills, moves, lines;
static unsigned transforms, concats, faults;
static int graphics_depth;
static void *last_fill;

static struct test_path *path_object(void *object) {
    uintptr_t address = (uintptr_t)object, base = (uintptr_t)paths;
    if (address < base || address >= base + sizeof paths ||
        (address - base) % sizeof paths[0]) return 0;
    return object;
}

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
void *sel_registerName(const char *name) {
    ++selector_calls;
    return intern(name);
}
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
    if (!strcmp(selector, "bezierPath")) {
        if (path_count == sizeof paths / sizeof paths[0]) return 0;
        return &paths[path_count++];
    }
    if (!strcmp(selector, "saveGraphicsState")) ++graphics_depth;
    if (!strcmp(selector, "restoreGraphicsState")) {
        if (graphics_depth <= 0) ++faults;
        --graphics_depth;
    }
    if (!strcmp(selector, "moveToPoint:")) ++moves;
    if (!strcmp(selector, "lineToPoint:")) ++lines;
    if (!strcmp(selector, "translateXBy:yBy:")) ++transforms;
    if (!strcmp(selector, "concat")) ++concats;
    if (!strcmp(selector, "fill")) {
        struct test_path *path = path_object(object);
        if (!path || path->references != 1) ++faults;
        last_fill = object;
        ++fills;
    }
    if (!strcmp(selector, "retain")) {
        struct test_path *path = path_object(object);
        if (path) { ++path->references; ++path_retains; }
        ++retains;
    }
    if (!strcmp(selector, "release")) {
        struct test_path *path = path_object(object);
        if (path) {
            if (path->references != 1) ++faults;
            --path->references;
            ++path_releases;
        }
        --retains;
    }
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

/* Counters check resource/dispatch behavior, not AppKit rendering speed. */
int test_counter(int which) {
    switch (which) {
        case 0: return selector_calls;
        case 1: return path_count;
        case 2: return path_retains;
        case 3: return path_releases;
        case 4: return fills;
        case 5: return moves;
        case 6: return lines;
        case 7: return transforms;
        case 8: return concats;
        case 9: return graphics_depth;
        case 10: return faults;
        default: return -1;
    }
}
void *test_last_fill(void) { return last_fill; }
