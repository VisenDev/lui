"""Exercise the shared demo through real raw terminal I/O on a POSIX PTY.

Run `python3 tests/terminal.py` for SBCL, CLISP and ECL, or pass --lisp sbcl.
The optional backend needs uncursed and its dependencies registered with ASDF.
"""

import argparse
import errno
import fcntl
import os
from pathlib import Path
import pty
import re
import select
import shutil
import struct
import subprocess
import tempfile
import termios
import time

from terminal_screen import Screen

ROOT = Path(__file__).resolve().parents[1]


def script(error=False, debug=False):
    # These assertions inspect Glass colors and Unicode borders explicitly.
    draw = """(let ((frames 0) (draw (lui.example.demo:make-demo)))
  (handler-case
      (lui:run (lambda ()
                 (funcall draw)
                 (lui.frame:request-frame 0.03)
                 (when (> (incf frames) 1) (error "test draw failure")))
               :backend :terminal)
    (error () (format t "~&@@DRAW-ERROR~%"))))""" if error else """
(let* ((gallery (lui.example.demo:make-gallery :toolkit :glass))
       (context (lui:run (lambda () (lui.example.demo:draw gallery))
                         :backend :terminal)))
  (format t "~&@@RESULT name=~S volume=~,2F enabled=~S count=~D size=~Dx~D~%"
          (lui.example.demo::gallery-name gallery)
          (lui.example.demo::gallery-volume gallery)
          (lui.example.demo::gallery-enabled gallery)
          (lui.example.demo::gallery-count gallery) (lui.frame:context-width context)
          (lui.frame:context-height context)))"""
    if debug:
        draw = """
(let* ((gallery (lui.example.demo:make-gallery :toolkit :glass))
       (state (lui.debug:make-debugger-state :open-p t :width 30))
       (first t)
       (context (lui:run (lambda ()
                           (when first
                             (setf first nil)
                             (lui.debug:set-debugger-enabled t :state state))
                           (lui.example.demo:draw gallery))
                         :backend :terminal)))
  (format t "~&@@DEBUG width=~,1F size=~Dx~D~%"
          (lui.debug:debugger-state-width state)
          (lui.frame:context-width context) (lui.frame:context-height context)))

"""
    return f"""(load "scripts/setup.lisp")
(handler-case (asdf:load-system "cffi")
  (error () (uiop:symbol-call :ql :quickload "cffi" :silent t)))
(asdf:load-system "lui/terminal")
(asdf:load-system "lui/demo")
(defun test-mouse (input sequence &optional context)
  (let* ((*standard-input* (make-string-input-stream
                            (concatenate 'string (string #\\Escape) "[<" sequence)))
         (event (uncursed-sys:read-event)))
    (lui.terminal::mouse-event input (uncursed:event-kind event) context)))
(assert (= (lui:terminal-text-width "A界é") 4))
(assert (equalp (lui.terminal:text-lines "界 ab" 3) #("界" "ab")))
(let ((context (lui.terminal:make-terminal-context)))
  (lui.frame:with-frame (context 4 1) (lui.glass:label "A界é"))
  (assert (string= (lui.terminal:render-terminal context)
                   (format nil "A界é~%"))))
(let ((context (lui.terminal:make-terminal-context)))
  (lui.frame:with-frame (context 8 3)
    (lui.motif:panel (lui:opt :width (lui.layout:fixed 4)
                              :height (lui.layout:fixed 3) :padding 1)
      (lui.motif:label "X")))
  (assert (string= (lui.terminal:render-terminal context)
                   (format nil "+--+    ~%|X |    ~%+--+    ~%"))))
(let ((context (lui.terminal:make-terminal-context)))
  (lui.frame:with-frame (context 8 3)
    (lui.glass:panel (lui:opt :width (lui.layout:fixed 4)
                              :height (lui.layout:fixed 3) :padding 1)
      (lui.glass:label "X")))
  (assert (string= (lui.terminal:render-terminal context)
                   (format nil "╭──╮    ~%│X │    ~%╰──╯    ~%"))))
;; Text border glyphs are independent of a toolkit's graphical radius.
(lui.fn:fn test-panel-border ((toolkit symbol) (radius real) (border string)
                             &rest options)
  (let ((context (lui.terminal:make-terminal-context)))
    (lui.frame:with-frame (context 5 3)
      (lui:with-toolkit (toolkit)
        (lui:panel (append options (lui:opt :id :border :radius radius
                          :width (lui.layout:fixed 5)
                          :height (lui.layout:fixed 3) :padding 0)))))
    (assert (= radius (lui.widgets:widget-radius
                       (lui.layout:element-content
                        (gethash (lui:widget-id :border context) (lui.frame::context-ids context))))))
    (assert (string= (lui.terminal:render-terminal context)
                     (format nil "~C~A~C~%~C   ~C~%~C~A~C~%"
                             (char border 0) (make-string 3 :initial-element (char border 4))
                             (char border 1) (char border 5) (char border 5)
                             (char border 2) (make-string 3 :initial-element (char border 4))
                             (char border 3))))))
(test-panel-border :glass 0 "╭╮╰╯─│")
(test-panel-border :motif 12 "++++-|")
(test-panel-border :garnet 12 "++++-|")
(lui:register-toolkit :terminal-border-test :parent :glass
                     :defaults '(:terminal-border "┌┐└┘═║"))
(dolist (radius '(0 14))
  (test-panel-border :terminal-border-test radius "┌┐└┘═║"))
(test-panel-border :glass 0 "++++-|" :terminal-border "++++-|")
;; Explicit NIL restores radius-based fallback instead of inheriting defaults.
(test-panel-border :terminal-border-test 0 "++++-|" :terminal-border nil)
(test-panel-border :terminal-border-test 14 "╭╮╰╯─│" :terminal-border nil)
(let ((context (lui.terminal:make-terminal-context))
      (gallery (lui.example.demo:make-gallery :toolkit :glass)))
  (lui.frame:with-frame (context 90 35) (lui.example.demo:draw gallery))
  (let ((lines (lui.terminal:text-lines (lui.terminal:render-terminal context) nil)))
    (assert (string= (aref lines 0) (format nil "╭~A╮" (make-string 88 :initial-element #\\─))))
    (assert (string= (aref lines 34) (format nil "╰~A╯" (make-string 88 :initial-element #\\─))))))
;; Track endpoints agree with keyboard and raw mouse edits.
(let ((context (lui.terminal:make-terminal-context)) (value 0.5))
  (flet ((draw ()
           (setf value (lui.motif:slider (lui:opt :id :slide :value value :width (lui.layout:fixed 20) :step 0.25)))))
    (dolist (entry '((0 "#---------------- 0%")
                     (0.5 "========#------- 50%")
                     (1 "==============# 100%")))
      (setf value (first entry))
      (lui.frame:with-frame (context 20 2) (draw))
      (assert (string= (second entry)
                       (subseq (lui.terminal:render-terminal context) 0 20))))
    (setf value 0.5)
    (lui.frame:with-frame (context 20 2) (draw))
    (dolist (entry '((16 1) (1 0) (9 0.5)))
      (let ((input (lui.terminal::make-input)))
        (test-mouse input
          (format nil "0;~D;1M" (first entry)) context)
        (lui.frame:with-frame
            (context 20 2 :events
              (reverse (lui.terminal::input-events input)))
          (draw))
        (assert (= value (second entry)))))
    (dolist (entry '((:home 0) (:end 1) (:left 0.75) (:right 1)))
      (lui.frame:with-frame
          (context 20 2 :events
            (list (lui.frame:make-event :kind :key :id :slide
                                       :key (first entry))))
        (draw))
      (assert (= value (second entry))))))
(dolist (width '(1 2 3))
  (let ((context (lui.terminal:make-terminal-context)))
    (lui.frame:with-frame (context width 1)
      (lui.motif:slider (lui:opt :id :narrow :value 0.5 :width (lui.layout:fixed width))))
    (let ((line (lui.terminal:render-terminal context)))
      (assert (= (1+ width) (lui:terminal-text-width line)))
      (assert (find #\\# line)))))
(let ((context (lui.terminal:make-terminal-context)))
  (lui.frame:with-frame (context 12 1)
    (lui.frame:column (:width (lui.layout:fixed 10) :clip-p t)
      (lui.motif:slider (lui:opt :id :clipped :value 1 :width (lui.layout:fixed 20)))))
  (let ((line (lui.terminal:render-terminal context)))
    (assert (char= (char line 10) #\\Space))
    (assert (char= (char line 11) #\\Space))
    (assert (not (find #\\# line)))))
;; Mouse cells use their centers, matching rounded fractional painted bounds.
(dolist (start '(1/4 1/2 3/4))
  (let ((context (lui.terminal:make-terminal-context))
        (clicks 0) (checked nil) (value 0.5))
    (labels ((draw ()
               (when (lui:button "Click" (lui:opt :id :fractional-button :floating-p t :offset-x start :offset-y start
                                :width (lui.layout:fixed 8)
                                :height (lui.layout:fixed 1)))
                 (incf clicks))
               (setf checked
                 (lui:checkbox "Enabled" (lui:opt :id :fractional-check :value checked :floating-p t :offset-x start
                            :offset-y (+ 2 start) :width (lui.layout:fixed 12)
                            :height (lui.layout:fixed 1))))
               (setf value
                 (lui:slider (lui:opt :id :fractional-slider :value value :floating-p t :offset-x start
                            :offset-y (+ 4 start) :width (lui.layout:fixed 20)
                            :height (lui.layout:fixed 1) :step 0.01))))
             (mouse (button x y &optional release)
               (let ((input (lui.terminal::make-input)))
                 (test-mouse
                   input (format nil "~D;~D;~D~A" button x y
                                 (if release "m" "M")) context)
                 (lui.frame:with-frame
                     (context 24 7 :events
                       (reverse (lui.terminal::input-events input)))
                   (draw)))))
      (lui.frame:with-frame (context 24 7) (draw))
      (let ((cell (1+ (floor (+ start 1/2)))))
        (mouse 0 cell cell)
        (mouse 0 cell cell t)
        (assert (= clicks 1))
        (mouse 0 cell (+ cell 2))
        (mouse 0 cell (+ cell 2) t)
        (assert checked)
        (mouse 0 cell (+ cell 4))
        (assert (zerop value))
        (mouse 32 40 (+ cell 4))
        (assert (= value 1))
        (mouse 32 1 (+ cell 4))
        (assert (zerop value))
        (mouse 0 1 (+ cell 4) t)
        (assert (null (lui:widget-key (lui.frame:context-active context))))))))
;; Sliders behind overlays cannot steal their presses or a batched drag.
(let ((context (lui.terminal:make-terminal-context))
      (behind 0.5) (visible 0.5) (clicks 0))
  (labels ((draw ()
             (setf behind (lui:slider (lui:opt :id :behind :value behind :width (lui.layout:fixed 20)
                                     :height (lui.layout:fixed 1))))
             (setf visible (lui:slider (lui:opt :id :visible :value visible :width (lui.layout:fixed 20)
                                      :height (lui.layout:fixed 1))))
             (when (lui:button "Close" (lui:opt :id :overlay :floating-p t :width (lui.layout:fixed 20)
                              :height (lui.layout:fixed 1)))
               (incf clicks)))
           (batch (&rest sequences)
             (let ((input (lui.terminal::make-input)))
               (dolist (sequence sequences)
                 (test-mouse input sequence context))
               (lui.frame:with-frame
                   (context 20 2 :events
                     (reverse (lui.terminal::input-events input)))
                 (draw)))))
    (lui.frame:with-frame (context 20 2) (draw))
    (batch "0;3;1M" "0;3;1m")
    (assert (= clicks 1))
    (assert (= behind 0.5))
    (batch "0;3;1M" "32;3;2M" "32;3;1M" "0;3;1m")
    (assert (= clicks 2))
    (assert (= behind 0.5))
    (assert (= visible 0.5))
    (batch "0;1;2M" "32;30;1M" "0;30;1m")
    (assert (= visible 1))
    (assert (= behind 0.5))
    (batch "0;1;2M")
    (assert (zerop visible))
    (batch "35;30;1M" "32;30;1M")
    (assert (zerop visible))
    (assert (null (lui:widget-key (lui.frame:context-active context))))
    (batch "0;1;2M" "32;30;1M" "0;30;1m")
    (assert (= visible 1))))
;; Shared gauge/canvas values have useful plain and colored representations.
(let ((context (lui.terminal:make-terminal-context)))
  (lui.frame:with-frame (context 20 1)
    (lui.widgets:declare-widget :gauge :motif :progress "" :value 0.5))
  (assert (search "[#####.....] 50%"
                  (lui.terminal:render-terminal context))))
(let ((context (lui.terminal:make-terminal-context)))
  (lui.frame:with-frame (context 5 5)
    (lui.motif:panel (lui:opt :width (lui.layout:grow) :height (lui.layout:grow))
      (lui.widgets:declare-widget
       :canvas :motif :circles "" :width (lui.layout:fixed 5)
       :height (lui.layout:fixed 5)
       :value '((:circle 2.5 2.5 2 "#ff0000" "#00ff00")))))
  (let ((plain (lui.terminal:render-terminal context))
        (colored (lui.terminal:render-terminal context :ansi t)))
    (assert (search "+---+" plain))
    (assert (find #\\o plain))
    (assert (find #\\. plain))
    (format t "~&@@ANSI-CANVAS-BEGIN~%~A@@ANSI-CANVAS-END~%" colored)))
(let ((input (lui.terminal::make-input)))
  (test-mouse input "2;3;4M")
  (assert (eq (lui.frame:event-button
               (first (lui.terminal::input-events input))) :secondary))
  (test-mouse input "32;3;4M")
  (assert (lui.frame:event-dragging-p
           (first (lui.terminal::input-events input))))
  (test-mouse input "35;3;4M")
  (assert (not (lui.frame:event-dragging-p
                (first (lui.terminal::input-events input))))))
;; Physical SGR state distinguishes released motion from a retained capture.
(dolist (entry '(("0;3;4M" 1) ("32;3;4M" 1) ("0;3;4m" 0)
                 ("35;3;4M" 0) ("2;3;4M" 2) ("34;3;4M" 2)
                 ("64;3;4M" nil)))
  (let ((input (lui.terminal::make-input)))
    (test-mouse input (first entry))
    (assert (eql (second entry)
                 (lui.frame:event-buttons
                   (first (lui.terminal::input-events input)))))))
;; Fractional cell boundaries must agree for painting and clipping.
(let ((context (lui.terminal:make-terminal-context)))
  (lui.frame:with-frame (context 10 4)
    (lui.frame:row (:width (lui.layout:grow) :height (lui.layout:grow))
      (lui.motif:panel (lui:opt :width (lui.layout:fixed 2.4)
                                :height (lui.layout:grow)))
      (lui.motif:panel (lui:opt :width (lui.layout:grow) :height (lui.layout:grow)
                                :padding 1)
        (lui.motif:label "X"))))
  (let ((lines (lui.terminal:text-lines
                (lui.terminal:render-terminal context) nil)))
    (assert (char= (char (aref lines 0) 2) #\\+))
    (assert (char= (char (aref lines 1) 2) #\\|))
    (assert (char= (char (aref lines 3) 2) #\\+))))
;; A zero-padding child cannot overwrite its enclosing panel's borders.
(let ((context (lui.terminal:make-terminal-context)))
  (lui.frame:with-frame (context 5 3)
    (lui.garnet:panel (lui:opt :width (lui.layout:grow) :height (lui.layout:grow))
      (lui.garnet:label "XXXXX")))
  (let ((plain (lui.terminal:render-terminal context))
        (colored (lui.terminal:render-terminal context :ansi t)))
    (assert (string= plain (format nil "+---+~%|   |~%+---+~%")))
    (assert (not (find #\\Escape plain)))
    (format t "~&@@ANSI-GARNET-BEGIN~%~A@@ANSI-GARNET-END~%" colored)))
(let ((context (lui:run (lui.example.demo:make-demo) :backend :terminal
                        :width 90 :height 35 :interactive nil)))
  (lui.layout:walk-elements
   (lui.frame:context-root context)
   (lambda (node)
     (when (eq (lui:widget-key (lui.layout:element-id node)) :name)
       (let ((box (lui.layout:element-box node)))
         (format t "~&@@NAME=~D,~D~%"
                 (1+ (floor (lui.layout:box-x box)))
                 (1+ (floor (lui.layout:box-y box))))))
     (when (member (lui:widget-key (lui.layout:element-id node))
                   '((:page :controls) (:page :editing) (:page :layout))
                   :test #'equal)
       (let ((box (lui.layout:element-box node)))
         (format t "~&@@TAB-~A=~D,~D~%"
                 (second (lui:widget-key (lui.layout:element-id node)))
                 (1+ (lui.terminal:cell-edge (lui.layout:box-x box)))
                 (1+ (lui.terminal:cell-edge (lui.layout:box-y box))))))
     (when (eq (lui:widget-key (lui.layout:element-id node)) :reset)
       (let ((box (lui.layout:element-box node)))
         (format t "~&@@RESET=~D,~D~%"
                 (1+ (floor (lui.layout:box-x box)))
                 (1+ (floor (lui.layout:box-y box)))))))))
{draw}
"""


def command(lisp, path):
    return {
        "sbcl": ["sbcl", "--script", str(path)],
        "clisp": ["clisp", "-q", "-q", str(path)],
        "ecl": ["ecl", "-shell", str(path)],
    }[lisp]


class Terminal:
    def __init__(self, cmd, term="xterm-direct"):
        self.master, self.slave = pty.openpty()
        self.before = termios.tcgetattr(self.slave)
        self.screen = Screen(90, 35)
        self.resize(90, 35)
        self.output = b""
        environment = os.environ.copy()
        if term is None:
            environment.pop("TERM", None)
        else:
            environment["TERM"] = term
        software = Path.home() / "quicklisp/dists/quicklisp/software"
        environment["CL_SOURCE_REGISTRY"] = (
            f'(:source-registry (:directory "{ROOT}/") '
            f'(:tree "{software}/") :ignore-inherited-configuration)'
        )
        cache = Path(cmd[-1]).parent / "cache"
        environment["ASDF_OUTPUT_TRANSLATIONS"] = (
            f'(:output-translations (t "{cache}/") :ignore-inherited-configuration)'
        )
        self.process = subprocess.Popen(
            cmd, cwd=ROOT, stdin=self.slave, stdout=self.slave,
            stderr=self.slave, start_new_session=True, env=environment,
        )

    def resize(self, columns, rows):
        self.screen.resize(columns, rows)
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ,
                    struct.pack("HHHH", rows, columns, 0, 0))

    def pump(self, seconds=0.1):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            ready, _, _ = select.select([self.master], [], [],
                                        max(0, end - time.monotonic()))
            if not ready:
                break
            try:
                chunk = os.read(self.master, 65536)
            except OSError as exc:
                if exc.errno == errno.EIO:
                    break
                raise
            if not chunk:
                break
            self.output += chunk
            try:
                self.screen.feed(chunk)
            except AssertionError as error:
                raise AssertionError(f"{error}\nRaw process output:\n" +
                                     self.output.decode("utf-8", "replace")) from error

    def until(self, needle, timeout=30):
        end = time.monotonic() + timeout
        while needle not in self.output and time.monotonic() < end:
            self.pump()
            if self.process.poll() is not None:
                self.pump()
                break
        assert needle in self.output, self.output.decode("utf-8", "replace")

    def until_visible(self, text, timeout=30):
        end = time.monotonic() + timeout
        while text not in self.screen and time.monotonic() < end:
            self.pump()
            if self.process.poll() is not None:
                break
        assert text in self.screen, self.screen.text + "\nRaw process output:\n" + self.output.decode("utf-8", "replace")

    def settle(self, idle=0.1, timeout=5):
        """Wait for a completed output burst, including trailing focus overlays."""
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            checkpoint = len(self.output)
            self.pump(idle)
            if len(self.output) == checkpoint:
                assert not self.screen._pending and not self.screen._decoder.getstate()[0], "Incomplete terminal output"
                return
        raise AssertionError("Terminal output did not settle")

    def frame(self):
        self.settle()
        return self.screen.snapshot()

    def send(self, data):
        os.write(self.master, data)
        self.pump(0.25)

    def restored(self):
        self.process.wait(timeout=10)
        self.pump()
        assert self.process.returncode == 0, self.output.decode("utf-8", "replace")
        assert termios.tcgetattr(self.slave) == self.before, "termios not restored"
        assert re.search(rb"\x1b\[\?(?:12;)?25h", self.output), "Cursor not restored"
        for sequence in (b"\x1b[?1049l", b"\x1b[?1006l",
                         b"\x1b[?1003l"):
            assert sequence in self.output, f"Missing cleanup: {sequence!r}"

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
            self.process.wait()
        os.close(self.master)
        os.close(self.slave)


def text_style(frame, text):
    positions = frame.positions(text)
    assert positions, frame.text
    x, y = positions[-1]
    return frame.cells[y][x][1:4]


def text_position(frame, text, last=True):
    positions = frame.positions(text)
    assert positions, frame.text
    x, y = positions[-1 if last else 0]
    return x + 1, y + 1


def divider_position(frame):
    """Find the accent rail in reconstructed cells, excluding panel borders."""
    properties = frame.positions("Properties")
    bottom = properties[0][1] if properties else frame.rows
    for y in reversed(range(bottom)):
        row = frame.cells[y]
        text = "".join(cell[0] for cell in row)
        for match in reversed(list(re.finditer("─{8,}", text))):
            style = row[match.start()][1:3]
            if (37, 139, 255) in style:
                return match.start() + len(match[0]) // 2 + 1, y + 1
    raise AssertionError(frame.text)


def properties_close(frame):
    """Locate the properties pane's close control beside its heading."""
    heading = frame.positions("Properties")
    assert heading, frame.text
    x, y = heading[-1]
    candidates = [(cx, cy) for cx, cy in frame.positions("×") if cy == y and cx > x]
    assert candidates, frame.text
    cx, cy = candidates[0]
    return cx + 1, cy + 1


def check_colored_snapshots(output):
    """Check combined or separate SGR attributes through the shared normalizer."""
    snapshots = {}
    for name, rows in (("CANVAS", 5), ("GARNET", 3)):
        marker = name.encode()
        match = re.search(b"@@ANSI-" + marker + b"-BEGIN\r?\n(.*?)@@ANSI-" + marker + b"-END", output, re.S)
        assert match, name
        snapshots[name] = Screen(5, rows + 1).feed(match[1])
    canvas = [cell for row in snapshots["CANVAS"].cells for cell in row]
    assert any(cell[0] == "o" and cell[1] == (255, 0, 0) for cell in canvas)
    assert any(cell[0] == "." and cell[2] == (0, 255, 0) for cell in canvas)
    garnet = snapshots["GARNET"]
    assert garnet.cells[0][0][:3] == ("+", (0, 0, 0), (255, 255, 255))


def exercise(lisp, path):
    terminal = Terminal(command(lisp, path))
    try:
        terminal.until(b"\x1b[?1049h", timeout=180)
        terminal.until_visible(b"Common Lisp")
        check_colored_snapshots(terminal.output)
        assert any(isinstance(cell[1], tuple) and isinstance(cell[2], tuple)
                   for row in terminal.screen.cells for cell in row)
        assert not termios.tcgetattr(terminal.slave)[3] & termios.ICANON
        terminal.pump(0.2)
        checkpoint = len(terminal.output)
        terminal.pump(0.25)
        assert len(terminal.output) == checkpoint, "Idle frames are repainting"
        assert b"\x1b[?1003h" in terminal.output
        tabs = {}
        for name, x, y in re.findall(rb"@@TAB-(\w+)=(\d+),(\d+)",
                                      terminal.output):
            tabs[name] = (int(x), int(y))
        x, y = tabs[b"LAYOUT"]
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        frame = terminal.frame()
        assert b"[ Layout ]" in frame and b"[ Controls ]" not in frame
        assert text_style(frame, b"[ Layout ]")[1] == (37, 139, 255)
        # Hover is underline/accent text, distinct from the selected tab fill.
        x, y = tabs[b"EDITING"]
        terminal.send(f"\x1b[<35;{x};{y}M".encode())
        frame = terminal.frame()
        assert text_style(frame, b"  Editing  ") == (
            (37, 139, 255), (48, 48, 64), True)
        assert text_style(frame, b"[ Layout ]")[1] == (37, 139, 255)
        terminal.send(b"\x1b[<35;1;1M")
        frame = terminal.frame()
        assert text_style(frame, b"  Editing  ") == (
            (255, 255, 255), (48, 48, 64), False)
        # Labels inherit the window color instead of painting shaded rectangles.
        assert text_style(frame, b"LUI feature gallery")[1] == (32, 36, 48)
        x, y = tabs[b"CONTROLS"]
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        match = re.search(rb"@@NAME=(\d+),(\d+)", terminal.output)
        assert match, terminal.output
        x, y = (int(value) for value in match.groups())
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        # Shift-Tab reaches 7GUIs; Left selects the preceding Styles tab.
        terminal.send(b"\x1b[Z\x1b[D")
        terminal.until_visible(b"Customize the active toolkit")
        terminal.send(b"\x1b[H")
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        terminal.send(b"\x1b")
        terminal.send(b"\x01\x0bTerminal")
        # Space in a text field inserts a character, then Ctrl-H removes it.
        terminal.send(b" \x08")
        # UTF-8 and CSI input may arrive in separate reads.
        terminal.send("界".encode("utf-8")[:1])
        terminal.send("界".encode("utf-8")[1:])
        terminal.send(b"\x1b[")
        terminal.send(b"D\x7f")
        terminal.send(b"l")
        # Backspace before the final wide character, then replace that character.
        terminal.send(b"\x1b[F\x7f!")
        terminal.send(b"\x01\x06\x04e\x05\x08!\x15\x19")
        terminal.send(b"\x17\x19\x14\x14")
        terminal.send(b"\t\x1b[C\t \t\r")
        terminal.until_visible(b"(1)")
        terminal.send(b"\x1b[Z\r")
        assert b"[x] Enabled" in terminal.frame()
        terminal.send(b" ")
        assert b"[ ] Enabled" in terminal.frame()
        terminal.send(b"\t ")
        terminal.until_visible(b"(2)")
        terminal.send(b"\r")
        terminal.until_visible(b"(3)")
        # Hit the shared demo's actual Reset geometry, including panel padding.
        match = re.search(rb"@@RESET=(\d+),(\d+)", terminal.output)
        assert match, terminal.output
        x, y = (int(value) for value in match.groups())
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        terminal.resize(100, 40)
        terminal.pump(0.4)
        # An incomplete escape sequence must not trap the emergency quit key.
        terminal.send(b"\x1b[\x11")
        terminal.until(b"@@RESULT")
        terminal.restored()
        result = terminal.output.split(b"@@RESULT", 1)[1]
        assert b'name="Terminal!"' in result, result
        assert b"volume=0.41" in result, result
        assert b"enabled=NIL" in result, result
        assert b"count=0" in result, result
        assert b"size=100x40" in result, result
    finally:
        terminal.close()


def exercise_debugger(lisp, path):
    terminal = Terminal(command(lisp, path))
    try:
        terminal.until(b"\x1b[?1049h", timeout=180)
        terminal.until_visible(b"Layout debugger")
        terminal.pump(0.2)
        # Unit-size rows expose the tab nodes without oversized disclosure pills.
        assert terminal.frame().count(b"TAB (PAGE") >= 5
        # Initial width30 in90columns: handle centered at x60 (zero based).
        terminal.send(b"\x1b[<0;61;4M")
        terminal.send(b"\x1b[<32;51;4M\x1b[<0;51;4m")
        terminal.send(b"\x1b[D")
        terminal.resize(100, 30)
        terminal.pump(0.4)
        frame = terminal.frame()
        assert b"Layout debugger" in frame
        assert frame.rows == 30 and frame.columns == 100
        assert all(len(row) == 100 for row in frame.cells)
        assert "│".encode() in frame
        assert not any(cell[0] == "(" and cell[1:3] == ("default-bg", "default-fg")
                       for row in frame.cells for cell in row), "Resize rail repainted as a button"
        assert text_style(frame, "│".encode())[:2] == (
            (48, 48, 64), (37, 139, 255))
        # Select a real tree row, then resize its properties through the rail.
        x, y = text_position(frame, b"PANEL WINDOW")
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        frame = terminal.frame()
        assert b"Geometry" in frame
        x, y = divider_position(frame)
        terminal.send(f"\x1b[<0;{x};{y}M".encode())
        terminal.send(f"\x1b[<32;{x};{y - 3}M\x1b[<0;{x};{y - 3}m".encode())
        frame = terminal.frame()
        _, grown_y = divider_position(frame)
        assert grown_y < y
        terminal.send(b"\x1b[B")
        assert divider_position(terminal.frame())[1] > grown_y
        terminal.send(b"\x1b[A\x1b[H")
        assert b"Close" in terminal.frame()
        for _ in range(16):
            if b"Input" in terminal.frame():
                break
            terminal.send(b"\x1b[<65;85;16M")
        frame = terminal.frame()
        assert b"Input" in frame, frame.decode("utf-8", "replace")
        terminal.send(b"\x1b[B" * 8)
        frame = terminal.frame()
        x, y = text_position(frame, b"PANEL WINDOW", last=False)
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        frame = terminal.frame()
        assert b"Geometry" not in frame
        x, y = text_position(frame, b"PANEL WINDOW", last=False)
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        x, y = divider_position(terminal.frame())
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        terminal.send(b"\x1b[F")
        frame = terminal.frame()
        assert b"Geometry" not in frame
        x, y = text_position(frame, b"PANEL WINDOW", last=False)
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        x, y = divider_position(terminal.frame())
        terminal.send(f"\x1b[<0;{x};{y}M".encode())
        terminal.send(f"\x1b[<32;{x};31M\x1b[<0;{x};31m".encode())
        frame = terminal.frame()
        assert b"Geometry" not in frame
        x, y = text_position(frame, b"PANEL WINDOW", last=False)
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        frame = terminal.frame()
        x, y = properties_close(frame)
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        frame = terminal.frame()
        assert b"Geometry" not in frame
        assert b"Layout debugger" in frame
        assert b"PANEL WINDOW" in frame
        # A no-button SGR move cancels a missed release without changing width.
        terminal.send(b"\x1b[<0;59;4M")
        terminal.send(b"\x1b[<35;30;4M\x1b[<35;20;4M")
        terminal.send(b"\x1b[<0;59;4M\x1b[<32;64;4M\x1b[<0;64;4m")
        terminal.send(b"\x1b[<0;64;4M\x1b[<32;59;4M\x1b[<0;59;4m")
        frame = terminal.frame()
        x, y = text_position(frame, b"PANEL WINDOW", last=False)
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        x, y = divider_position(terminal.frame())
        terminal.send(f"\x1b[<0;{x};{y}M".encode())
        terminal.send(f"\x1b[<35;{x};{y + 4}M".encode())
        assert divider_position(terminal.frame())[1] == y, (
            y, divider_position(terminal.frame()), "cancel moved rail")
        terminal.send(f"\x1b[<35;{x};{y + 6}M".encode())
        assert divider_position(terminal.frame())[1] == y, (
            y, divider_position(terminal.frame()), "cancel moved rail")
        terminal.send(f"\x1b[<0;{x};{y}M".encode())
        terminal.send(f"\x1b[<32;{x};{y - 2}M\x1b[<0;{x};{y - 2}m".encode())
        frame = terminal.frame()
        assert divider_position(frame)[1] < y
        x, y = properties_close(frame)
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        assert b"Geometry" not in terminal.frame()
        terminal.send(b"\x11")
        terminal.until(b"@@DEBUG")
        terminal.restored()
        result = terminal.output.split(b"@@DEBUG", 1)[1]
        assert b"width=42.0" in result, result
        assert b"size=100x30" in result, result
    finally:
        terminal.close()


def exercise_fallback(lisp, path):
    """Pipes and terminals without capabilities retain line-command input."""
    path.write_text("""(load "scripts/setup.lisp")
(asdf:load-system "lui/terminal")
(let ((context (lui:run (lambda () (lui:label "Fallback frame"))
                        :backend :terminal :width 24 :height 2)))
  (format t "~&@@FALLBACK ~Dx~D~%" (lui.frame:context-width context)
          (lui.frame:context-height context)))
""", encoding="utf-8")
    environment = os.environ.copy()
    environment["TERM"] = "xterm-direct"
    environment["ASDF_OUTPUT_TRANSLATIONS"] = (
        f'(:output-translations (t "{path.parent}/cache/") '
        ':ignore-inherited-configuration)'
    )
    result = subprocess.run(command(lisp, path), cwd=ROOT, env=environment,
                            input=b":quit\n", stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=180)
    assert result.returncode == 0, result.stdout.decode("utf-8", "replace")
    assert b"@@FALLBACK 24x2" in result.stdout
    assert b"\x1b[?1049h" not in result.stdout
    assert b"\x1b[?1003h" not in result.stdout
    for term in (None, "dumb"):
        terminal = Terminal(command(lisp, path), term=term)
        try:
            terminal.until(b"Fallback frame", timeout=180)
            assert termios.tcgetattr(terminal.slave) == terminal.before
            terminal.send(b":quit\n")
            terminal.until(b"@@FALLBACK 24x2")
            terminal.process.wait(timeout=10)
            assert terminal.process.returncode == 0
            assert b"\x1b[?1049h" not in terminal.output
            assert b"\x1b[?1003h" not in terminal.output
        finally:
            terminal.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lisp", choices=("sbcl", "clisp", "ecl"))
    args = parser.parse_args()
    implementations = [args.lisp] if args.lisp else ["sbcl", "clisp", "ecl"]
    with tempfile.TemporaryDirectory(prefix="lui-terminal-") as directory:
        path = Path(directory) / "run.lisp"
        for lisp in implementations:
            if not shutil.which(lisp):
                raise SystemExit(f"Missing Lisp implementation: {lisp}")
            path.write_text(script(), encoding="utf-8")
            exercise(lisp, path)
            path.write_text(script(error=True), encoding="utf-8")
            terminal = Terminal(command(lisp, path))
            try:
                terminal.until(b"@@DRAW-ERROR", timeout=180)
                terminal.restored()
            finally:
                terminal.close()
            path.write_text(script(debug=True), encoding="utf-8")
            exercise_debugger(lisp, path)
            exercise_fallback(lisp, path)
            print(f"{lisp}: raw input, Unicode, debugger drag/keyboard resize "
                  "restoration and redirected/TERM fallback pass")


if __name__ == "__main__":
    main()
