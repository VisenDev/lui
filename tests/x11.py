"""Native X11 window, rendering, convolution, input, and resize regressions.

Run python tests/x11.py with DISPLAY set. Requires SBCL, CFFI, zpb-ttf,
libX11/libXrender, ImageMagick import, and Pillow. Captures only LUI windows.
"""

from contextlib import contextmanager
import ctypes as C
from ctypes.util import find_library
import json
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"


class KeyEvent(C.Structure):
    _fields_ = [
        ("type", C.c_int), ("serial", C.c_ulong), ("send", C.c_int),
        ("display", C.c_void_p), ("window", C.c_ulong),
        ("root", C.c_ulong), ("subwindow", C.c_ulong), ("time", C.c_ulong),
        ("x", C.c_int), ("y", C.c_int), ("root_x", C.c_int),
        ("root_y", C.c_int), ("state", C.c_uint), ("code", C.c_uint),
        ("same_screen", C.c_int),
    ]


class ClientEvent(C.Structure):
    _fields_ = [
        ("type", C.c_int), ("serial", C.c_ulong), ("send", C.c_int),
        ("display", C.c_void_p), ("window", C.c_ulong),
        ("message_type", C.c_ulong), ("format", C.c_int),
        ("data", C.c_long * 5),
    ]


class Event(C.Union):
    _fields_ = [("key", KeyEvent), ("client", ClientEvent),
                ("padding", C.c_long * 24)]


class SetWindowAttributes(C.Structure):
    _fields_ = [("background_pixmap", C.c_ulong), ("background_pixel", C.c_ulong),
                ("border_pixmap", C.c_ulong), ("border_pixel", C.c_ulong),
                ("bit_gravity", C.c_int), ("win_gravity", C.c_int),
                ("backing_store", C.c_int), ("planes", C.c_ulong),
                ("pixel", C.c_ulong), ("save_under", C.c_int),
                ("event_mask", C.c_long), ("propagate", C.c_long),
                ("override", C.c_int), ("colormap", C.c_ulong),
                ("cursor", C.c_ulong)]


class WindowAttributes(C.Structure):
    _fields_ = [("x", C.c_int), ("y", C.c_int), ("width", C.c_int),
                ("height", C.c_int), ("border", C.c_int), ("depth", C.c_int),
                ("visual", C.c_void_p), ("root", C.c_ulong),
                ("class_", C.c_int), ("bit_gravity", C.c_int),
                ("win_gravity", C.c_int), ("backing_store", C.c_int),
                ("planes", C.c_ulong), ("pixel", C.c_ulong),
                ("save_under", C.c_int), ("colormap", C.c_ulong),
                ("map_installed", C.c_int), ("map_state", C.c_int),
                ("all_masks", C.c_long), ("your_mask", C.c_long),
                ("propagate", C.c_long), ("override", C.c_int),
                ("screen", C.c_void_p)]


class XErrorEvent(C.Structure):
    _fields_ = [("type", C.c_int), ("display", C.c_void_p),
                ("resource", C.c_ulong), ("serial", C.c_ulong),
                ("error", C.c_ubyte), ("request", C.c_ubyte),
                ("minor", C.c_ubyte)]


class Filters(C.Structure):
    _fields_ = [("count", C.c_int), ("names", C.POINTER(C.c_char_p)),
                ("alias_count", C.c_int), ("aliases", C.c_void_p)]


class X11:
    def __init__(self):
        self.lib = C.CDLL(find_library("X11"))
        signatures = {
            "XOpenDisplay": (C.c_void_p, [C.c_char_p]),
            "XDefaultRootWindow": (C.c_ulong, [C.c_void_p]),
            "XQueryTree": (C.c_int, [C.c_void_p, C.c_ulong,
                C.POINTER(C.c_ulong), C.POINTER(C.c_ulong),
                C.POINTER(C.POINTER(C.c_ulong)), C.POINTER(C.c_uint)]),
            "XFetchName": (C.c_int, [C.c_void_p, C.c_ulong, C.POINTER(C.c_void_p)]),
            "XFree": (C.c_int, [C.c_void_p]),
            "XFlush": (C.c_int, [C.c_void_p]),
            "XGetWindowAttributes": (C.c_int, [C.c_void_p, C.c_ulong,
                                               C.POINTER(WindowAttributes)]),
            "XMapRaised": (C.c_int, [C.c_void_p, C.c_ulong]),
            "XChangeWindowAttributes": (C.c_int, [C.c_void_p, C.c_ulong,
                C.c_ulong, C.POINTER(SetWindowAttributes)]),
            "XCloseDisplay": (C.c_int, [C.c_void_p]),
            "XSendEvent": (C.c_int, [C.c_void_p, C.c_ulong, C.c_int,
                C.c_long, C.POINTER(Event)]),
            "XStringToKeysym": (C.c_ulong, [C.c_char_p]),
            "XKeysymToKeycode": (C.c_uint, [C.c_void_p, C.c_ulong]),
            "XInternAtom": (C.c_ulong, [C.c_void_p, C.c_char_p, C.c_int]),
            "XResizeWindow": (C.c_int, [C.c_void_p, C.c_ulong,
                C.c_uint, C.c_uint]),
        }
        for name, (result, arguments) in signatures.items():
            function = getattr(self.lib, name)
            function.restype = result
            function.argtypes = arguments
        self.errors = []
        def handle_error(display, pointer):
            event = C.cast(pointer, C.POINTER(XErrorEvent)).contents
            # Other desktop clients can disappear between tree/name queries.
            if not (event.error == 3 and event.request in (15, 20)):
                self.errors.append((event.error, event.request))
            return 0
        self.error_handler = C.CFUNCTYPE(C.c_int, C.c_void_p, C.c_void_p)(
            handle_error)
        self.lib.XSetErrorHandler.argtypes = [C.c_void_p]
        self.lib.XSetErrorHandler(self.error_handler)
        self.display = self.lib.XOpenDisplay(None)
        if not self.display:
            raise RuntimeError("DISPLAY must point to a running X server")
        self.root = self.lib.XDefaultRootWindow(self.display)

    def find(self, title, parent=None):
        parent = self.root if parent is None else parent
        root, owner, count = C.c_ulong(), C.c_ulong(), C.c_uint()
        children = C.POINTER(C.c_ulong)()
        if not self.lib.XQueryTree(self.display, parent, C.byref(root),
                                  C.byref(owner), C.byref(children), C.byref(count)):
            return None
        try:
            windows = list(children[:count.value])
        finally:
            if children:
                self.lib.XFree(children)
        for window in windows:
            name = C.c_void_p()
            if self.lib.XFetchName(self.display, window, C.byref(name)) and name:
                try:
                    if C.string_at(name).decode(errors="replace") == title:
                        return window
                finally:
                    self.lib.XFree(name)
            found = self.find(title, window)
            if found:
                return found
        return None

    def send(self, window, kind, x=0, y=0, code=0, state=0):
        event = Event()
        event.key = KeyEvent(type=kind, display=self.display, window=window,
                             root=self.root, x=x, y=y, code=code, state=state, same_screen=1)
        mask = {2: 1, 4: 4, 5: 8, 8: 32}[kind]
        assert self.lib.XSendEvent(self.display, window, 0, mask, C.byref(event))
        self.lib.XFlush(self.display)

    def click(self, window, bounds, fraction=0.5):
        x, y, width, height = bounds
        for kind in [4, 5]:
            self.send(window, kind, round(x + width * fraction),
                      round(y + height / 2), 1)

    def key(self, window, name, state=0):
        symbol = self.lib.XStringToKeysym(name.encode())
        code = self.lib.XKeysymToKeycode(self.display, symbol)
        self.send(window, 2, code=code, state=state)

    def activate(self, window):
        # A desktop may hide background windows. Keep only this test window
        # independent of its window manager so pixel capture is deterministic.
        attributes = SetWindowAttributes(override=1)
        self.lib.XChangeWindowAttributes(self.display, window, 1 << 9,
                                         C.byref(attributes))
        self.lib.XMapRaised(self.display, window)
        self.lib.XFlush(self.display)

    def close(self, window):
        event = Event()
        event.client = ClientEvent(
            type=33, display=self.display, window=window, format=32,
            message_type=self.lib.XInternAtom(self.display, b"WM_PROTOCOLS", 0),
        )
        event.client.data[0] = self.lib.XInternAtom(
            self.display, b"WM_DELETE_WINDOW", 0)
        self.lib.XSendEvent(self.display, window, 0, 0, C.byref(event))
        self.lib.XFlush(self.display)


def wait_for(function, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = function()
        if value:
            return value
        time.sleep(0.04)
    raise AssertionError("Timed out waiting for native window/state")


class X11Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.x = X11()
        BUILD.mkdir(exist_ok=True)

    @classmethod
    def tearDownClass(cls):
        cls.x.lib.XCloseDisplay(cls.x.display)
        if cls.x.errors:
            raise AssertionError(f"X11 test connection errors: {cls.x.errors}")

    @contextmanager
    def application(self, name, source):
        title = f"LUI X11 regression {name}"
        with tempfile.TemporaryDirectory(prefix="lui-x11-") as directory:
            directory = Path(directory)
            state = directory / "state.json"
            program = directory / "test.lisp"
            program.write_text('''(require :asdf)
(asdf:load-asd (truename "lui.asd"))
(asdf:load-system "lui/x11")
''' + source.replace("STATE_PATH", json.dumps(str(state))).replace(
                "WINDOW_TITLE", json.dumps(title)))
            with (directory / "output.log").open("w+") as log:
                process = subprocess.Popen(
                    ["sbcl", "--noinform", "--disable-debugger", "--load",
                     str(program), "--quit"], cwd=ROOT, stdout=log, stderr=log,
                )
                window = None
                try:
                    def locate():
                        if process.poll() is not None:
                            log.seek(0)
                            self.fail(log.read())
                        return self.x.find(title)
                    window = wait_for(locate)
                    self.x.activate(window)
                    time.sleep(0.3)
                    yield window, state
                    self.x.close(window)
                    process.wait(timeout=10)
                    log.seek(0)
                    output = log.read()
                    self.assertEqual(process.returncode, 0, output)
                    self.assertNotIn("X Error", output)
                    self.assertFalse(self.x.find(title))
                except Exception:
                    log.seek(0)
                    print(log.read())
                    raise
                finally:
                    if process.poll() is None:
                        if window:
                            self.x.close(window)
                        try:
                            process.wait(timeout=3)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()

    def state(self, path, predicate=lambda state: True):
        def read():
            try:
                state = json.loads(path.read_text())
                return state if predicate(state) else None
            except (FileNotFoundError, json.JSONDecodeError):
                return None
        return wait_for(read)

    def capture(self, window, name):
        path = BUILD / name
        attributes = WindowAttributes()
        self.x.lib.XGetWindowAttributes(self.x.display, window, C.byref(attributes))
        self.assertEqual(attributes.map_state, 2, "Test window is not viewable")
        subprocess.run(["import", "-window", hex(window), str(path)],
                       check=True, timeout=10)
        return Image.open(path).convert("RGB")

    def test_shared_demo_pixels_interaction_and_resize(self):
        source = r'''
(load "examples/demo.lisp")
(lui.x11:run-x11
 (lambda ()
   (lui.example:draw)
   (when (lui.frame:previous-box :hello)
     (with-open-file (stream STATE_PATH :direction :output
                             :if-exists :supersede)
       (format stream "{~S:~S,~S:~D,~S:~A,~S:~F,~S:~D,~S:~A,~S:{"
               "name" lui.example::*name* "count" lui.example::*count*
               "enabled" (if lui.example::*enabled* "true" "false")
               "volume" lui.example::*volume*
               "width" (round (lui.frame:context-width lui.frame:*context*))
               "hover" (if (lui.frame:context-hover lui.frame:*context*)
                           "true" "false")
               "bounds")
       (loop :for id :in '(:name :volume :enabled :hello :reset)
             :for first := t :then nil
             :for box := (lui.frame:previous-box id)
             :do (unless first (write-char #\, stream))
                 (format stream "~S:[~D,~D,~D,~D]"
                         (string-downcase (symbol-name id))
                         (round (lui.layout:box-x box))
                         (round (lui.layout:box-y box))
                         (round (lui.layout:box-width box))
                         (round (lui.layout:box-height box))))
       (write-string "}}" stream))))
 :title WINDOW_TITLE :width 720 :height 520)
'''
        with self.application("demo", source) as (window, path):
            state = self.state(path)
            image = self.capture(window, "x11.png")
            self.assertEqual(image.size, (720, 520))
            # Every widget must survive the final source-picture composite.
            # Counting varied pixels in each control catches last-item-only frames.
            for name, bounds in state["bounds"].items():
                x, y, width, height = bounds
                colors = image.crop((x, y, x + width, y + height)).getcolors(
                    width * height)
                self.assertGreater(len(colors), 8, name)
                self.assertGreater(sum(count for count, color in colors
                                       if max(color) > 150), 8, name)
            self.x.click(window, state["bounds"]["hello"])
            state = self.state(path, lambda s: s["count"] == 1)
            self.x.click(window, state["bounds"]["enabled"])
            state = self.state(path, lambda s: not s["enabled"])
            self.x.click(window, state["bounds"]["name"])
            self.x.key(window, "End")
            self.x.key(window, "a")
            state = self.state(path, lambda s: s["name"] == "Common Lispa")
            self.x.key(window, "a", state=4)
            self.x.key(window, "d", state=4)
            state = self.state(path, lambda s: s["name"] == "ommon Lispa")
            self.x.key(window, "e", state=4)
            self.x.key(window, "w", state=4)
            state = self.state(path, lambda s: s["name"] == "ommon ")
            self.x.key(window, "y", state=4)
            state = self.state(path, lambda s: s["name"] == "ommon Lispa")
            self.x.click(window, state["bounds"]["volume"], 0.75)
            state = self.state(path, lambda s: s["volume"] > 0.6)
            self.x.click(window, state["bounds"]["reset"])
            self.state(path, lambda s: s["count"] == 0 and s["hover"])
            self.x.send(window, 8)
            self.state(path, lambda s: not s["hover"])
            self.x.lib.XResizeWindow(self.x.display, window, 560, 420)
            self.x.lib.XFlush(self.x.display)
            self.state(path, lambda s: s["width"] == 560)
            # Let the resized frame reach the server before capturing it.
            time.sleep(0.15)
            resized = self.capture(window, "x11-resized.png")
            self.assertEqual(resized.size, (560, 420))

    def test_native_convolution_blurs_backdrop_inside_rounded_mask(self):
        source = r'''
(lui.x11:run-x11
 (lambda ()
   (lui.frame:column (:width (lui.layout:grow))
     (lui.glass:button
      :blur "" :width (lui.layout:fixed 240) :height (lui.layout:fixed 120)
      :painter
      (lambda (renderer node)
        (declare (ignore node))
        ;; Native stripes are drawn first; the glass callback samples them.
        (loop :for x :from 0 :below 240 :by 8
              :do (funcall (lui.draw:renderer-polygons renderer)
                           (list (lui.draw:rounded-polygon
                                  (lui.layout:make-box :x x :width 8 :height 120)
                                  0))
                           (if (evenp (/ x 8)) "#000000" "#ffffff") 1))
        (funcall (lui.draw:renderer-glass renderer)
                 (lui.layout:make-box :x 40 :y 20 :width 160 :height 80)
                 20 8)))))
 :title WINDOW_TITLE :width 240 :height 120)
'''
        for force_fallback in (False, True):
            prefix = "" if not force_fallback else r'''
(setf (symbol-function 'lui.x11::convolution-supported-p)
      (lambda (window) (declare (ignore window)) nil))
'''
            with self.subTest(fallback=force_fallback):
                with self.application("blur", prefix + source) as (window, path):
                    # Independently distinguish native support from its fallback.
                    render = C.CDLL(find_library("Xrender"))
                    render.XRenderQueryFilters.restype = C.POINTER(Filters)
                    render.XRenderQueryFilters.argtypes = [C.c_void_p, C.c_ulong]
                    filters = render.XRenderQueryFilters(self.x.display, window)
                    try:
                        names = ([] if not filters else [
                            filters.contents.names[i]
                            for i in range(filters.contents.count)])
                        supported = not force_fallback and b"convolution" in names
                    finally:
                        if filters:
                            self.x.lib.XFree(filters)
                    time.sleep(0.3)
                    filename = ("x11-no-blur.png" if force_fallback
                                else "x11-blur.png")
                    image = self.capture(window, filename)
                    if supported:
                        center = [image.getpixel((x, 60))[0] for x in range(70, 170)]
                        self.assertLess(max(center) - min(center), 128)
                        self.assertTrue(all(70 < value < 185 for value in center))
                    else:
                        self.assertEqual(image.getpixel((80, 60)), (0, 0, 0))
                    # Stripes outside the mask and in its cutout stay sharp.
                    self.assertEqual(image.getpixel((16, 60)), (0, 0, 0))
                    self.assertEqual(image.getpixel((24, 60)), (255, 255, 255))
                    self.assertEqual(image.getpixel((40, 20)), (255, 255, 255))


if __name__ == "__main__":
    unittest.main(verbosity=2)
