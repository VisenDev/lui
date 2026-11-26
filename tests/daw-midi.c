/* Test-only RtMidi C ABI double. Never load this library in an application. */
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

struct wrapper {
    void *object;
    void *callback;
#ifdef DAW_NEW_ABI
    void *error_callback;
#endif
    bool ok;
    const char *message;
};
struct state { unsigned next; bool open; };
static int live_inputs;
static int fail_read;
void lui_test_fail_read(void) { fail_read = 1; }
#ifdef DAW_NEW_ABI
void rtmidi_set_error_callback(void) {}
#endif
int lui_test_live_inputs(void) { return live_inputs; }
size_t lui_test_wrapper_size(void) { return sizeof(struct wrapper); }

struct wrapper *rtmidi_in_create(int api, const char *name, unsigned queue) {
    (void)api; (void)name; (void)queue;
    struct wrapper *w = calloc(1, sizeof(*w));
    w->object = calloc(1, sizeof(struct state));
    w->ok = true;
    ++live_inputs;
    return w;
}
void rtmidi_in_free(struct wrapper *w) {
    free(w->object); free(w); --live_inputs;
}
unsigned rtmidi_get_port_count(struct wrapper *w) { (void)w; return 1; }
int rtmidi_get_port_name(struct wrapper *w, unsigned index, char *out, int *len) {
    (void)w; (void)index;
    const char name[] = "LUI native test keyboard";
    if (out && *len >= (int)sizeof(name)) memcpy(out, name, sizeof(name));
    *len = sizeof(name);
    return 0;
}
void rtmidi_in_ignore_types(struct wrapper *w, bool sysex, bool clock,
                           bool sense) {
    w->ok = sysex && clock && sense;
    w->message = "Expected system-message filters";
}
void rtmidi_open_port(struct wrapper *w, unsigned index, const char *name) {
    (void)name;
    w->ok = index == 0;
    w->message = "Invalid input";
    ((struct state *)w->object)->open = w->ok;
}
void rtmidi_close_port(struct wrapper *w) {
    ((struct state *)w->object)->open = false;
}
double rtmidi_in_get_message(struct wrapper *w, unsigned char *out, size_t *len) {
    if (fail_read) {
        fail_read = 0;
        w->ok = false;
        w->message = NULL;
        *len = 0;
        return 0;
    }
    struct state *state = w->object;
    static const unsigned char messages[][3] = {
        {0x90, 72, 93}, {0xc0, 10, 0}, {0x80, 72, 0}
    };
    if (!state->open || state->next >= 3) { *len = 0; return 0; }
    unsigned index = state->next++;
    size_t count = index == 1 ? 2 : 3;
    if (*len < count) { w->ok = false; w->message = "Short buffer"; return 0; }
    memcpy(out, messages[index], count);
    *len = count;
    return index == 0 ? 0 : 0.125;
}
