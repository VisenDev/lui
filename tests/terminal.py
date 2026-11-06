"""Exercise the shared demo through real raw terminal I/O on a POSIX PTY.

Run `python3 tests/terminal.py` for SBCL, CLISP and ECL, or pass --lisp sbcl.
The optional backend needs CFFI registered with ASDF or installed in Quicklisp.
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

ROOT = Path(__file__).resolve().parents[1]


def script(error=False, debug=False):
    draw = """(let ((frames 0) (draw (lui.example:make-demo)))
  (handler-case
      (lui:run (lambda ()
                 (funcall draw)
                 (lui.frame:request-frame 0.03)
                 (when (> (incf frames) 1) (error "test draw failure")))
               :backend :terminal)
    (error () (format t "~&@@DRAW-ERROR~%"))))""" if error else """
(let* ((gallery (lui.example:make-gallery))
       (context (lui:run (lambda () (lui.example:draw gallery))
                         :backend :terminal)))
  (format t "~&@@RESULT name=~S volume=~,2F enabled=~S count=~D size=~Dx~D~%"
          (lui.example::gallery-name gallery)
          (lui.example::gallery-volume gallery)
          (lui.example::gallery-enabled gallery)
          (lui.example::gallery-count gallery) (lui.frame:context-width context)
          (lui.frame:context-height context)))"""
    if debug:
        draw = """
(let* ((gallery (lui.example:make-gallery))
       (state (lui.debug:make-state :open-p t :width 30))
       (first t)
       (context (lui:run (lambda ()
                           (when first
                             (setf first nil)
                             (lui.debug:set-enabled t :state state))
                           (lui.example:draw gallery))
                         :backend :terminal)))
  (format t "~&@@DEBUG width=~,1F size=~Dx~D~%"
          (lui.debug:state-width state)
          (lui.frame:context-width context) (lui.frame:context-height context)))

"""
    return f"""(let ((asdf (merge-pathnames "quicklisp/asdf.lisp"
                                   (user-homedir-pathname))))
  (when (probe-file asdf) (load asdf)))
(require :asdf)
(let ((setup (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file setup) (load setup)))
(handler-case (asdf:load-system "cffi")
  (error () (uiop:symbol-call :ql :quickload "cffi" :silent t)))
(asdf:load-asd (truename "lui.asd"))
(asdf:load-system "lui/terminal")
(asdf:load-system "lui/demo")
(assert (= (lui.terminal:text-width "A界é") 4))
(assert (equal (lui.terminal:text-lines "界 ab" 3) '("界" "ab")))
(let ((context (lui.terminal:make-terminal-context)))
  (lui.frame:with-frame (context 4 1) (lui.glass:label "A界é"))
  (assert (string= (lui.terminal:render-terminal context)
                   (format nil "A界é~%"))))
(let ((context (lui.terminal:make-terminal-context)))
  (lui.frame:with-frame (context 8 3)
    (lui.motif:panel (:width (lui.layout:fixed 4)
                      :height (lui.layout:fixed 3) :padding 1)
      (lui.motif:label "X")))
  (assert (string= (lui.terminal:render-terminal context)
                   (format nil "+--+    ~%|X |    ~%+--+    ~%"))))
(let ((context (lui.terminal:make-terminal-context)))
  (lui.frame:with-frame (context 8 3)
    (lui.glass:panel (:width (lui.layout:fixed 4)
                      :height (lui.layout:fixed 3) :padding 1)
      (lui.glass:label "X")))
  (assert (string= (lui.terminal:render-terminal context)
                   (format nil "╭──╮    ~%│X │    ~%╰──╯    ~%"))))
;; Track endpoints agree with keyboard and raw mouse edits.
(let ((context (lui.terminal:make-terminal-context)) (value 0.5))
  (flet ((draw ()
           (setf value (lui.motif:slider :slide value
                         :width (lui.layout:fixed 20) :step 0.25))))
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
      (let ((input (lui.terminal.io::make-input)))
        (lui.terminal.io::mouse-event input
          (format nil "0;~D;1M" (first entry)) context)
        (lui.frame:with-frame
            (context 20 2 :events
              (reverse (lui.terminal.io::input-events input)))
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
      (lui.motif:slider :narrow 0.5 :width (lui.layout:fixed width)))
    (let ((line (lui.terminal:render-terminal context)))
      (assert (= (1+ width) (lui.terminal:text-width line)))
      (assert (find #\\# line)))))
(let ((context (lui.terminal:make-terminal-context)))
  (lui.frame:with-frame (context 12 1)
    (lui.frame:column (:width (lui.layout:fixed 10) :clip-p t)
      (lui.motif:slider :clipped 1 :width (lui.layout:fixed 20))))
  (let ((line (lui.terminal:render-terminal context)))
    (assert (char= (char line 10) #\\Space))
    (assert (char= (char line 11) #\\Space))
    (assert (not (find #\\# line)))))
;; Shared gauge/canvas values have useful plain and colored representations.
(let ((context (lui.terminal:make-terminal-context)))
  (lui.frame:with-frame (context 20 1)
    (lui.widgets:declare-widget :gauge :motif :progress "" :value 0.5))
  (assert (search "[#####.....] 50%"
                  (lui.terminal:render-terminal context))))
(let ((context (lui.terminal:make-terminal-context)))
  (lui.frame:with-frame (context 5 5)
    (lui.motif:panel (:width (lui.layout:grow) :height (lui.layout:grow))
      (lui.widgets:declare-widget
       :canvas :motif :circles "" :width (lui.layout:fixed 5)
       :height (lui.layout:fixed 5)
       :value '((:circle 2.5 2.5 2 "#ff0000" "#00ff00")))))
  (let ((plain (lui.terminal:render-terminal context))
        (colored (lui.terminal:render-terminal context :ansi t)))
    (assert (search "+---+" plain))
    (assert (find #\\o plain))
    (assert (find #\\. plain))
    (assert (search "[38;2;255;0;0m" colored))
    (assert (search "[48;2;0;255;0m" colored))))
(let ((input (lui.terminal.io::make-input)))
  (lui.terminal.io::mouse-event input "2;3;4M")
  (assert (eq (lui.frame:event-button
               (first (lui.terminal.io::input-events input))) :secondary))
  (lui.terminal.io::mouse-event input "32;3;4M")
  (assert (lui.frame:event-dragging-p
           (first (lui.terminal.io::input-events input))))
  (lui.terminal.io::mouse-event input "35;3;4M")
  (assert (not (lui.frame:event-dragging-p
                (first (lui.terminal.io::input-events input))))))
;; Fractional cell boundaries must agree for painting and clipping.
(let ((context (lui.terminal:make-terminal-context)))
  (lui.frame:with-frame (context 10 4)
    (lui.frame:row (:width (lui.layout:grow) :height (lui.layout:grow))
      (lui.motif:panel (:width (lui.layout:fixed 2.4)
                        :height (lui.layout:grow)))
      (lui.motif:panel (:width (lui.layout:grow) :height (lui.layout:grow)
                        :padding 1)
        (lui.motif:label "X"))))
  (let ((lines (lui.terminal:text-lines
                (lui.terminal:render-terminal context) nil)))
    (assert (char= (char (first lines) 2) #\\+))
    (assert (char= (char (second lines) 2) #\\|))
    (assert (char= (char (fourth lines) 2) #\\+))))
;; A zero-padding child cannot overwrite its enclosing panel's borders.
(let ((context (lui.terminal:make-terminal-context)))
  (lui.frame:with-frame (context 5 3)
    (lui.garnet:panel (:width (lui.layout:grow) :height (lui.layout:grow))
      (lui.garnet:label "XXXXX")))
  (let ((plain (lui.terminal:render-terminal context))
        (colored (lui.terminal:render-terminal context :ansi t)))
    (assert (string= plain (format nil "+---+~%|   |~%+---+~%")))
    (assert (not (find #\\Escape plain)))
    (assert (search "[38;2;0;0;0m" colored))
    (assert (search "[48;2;255;255;255m" colored))))
(let ((context (lui:run (lui.example:make-demo) :backend :terminal
                        :width 90 :height 35 :interactive nil)))
  (lui.layout:walk-elements
   (lui.frame:context-root context)
   (lambda (node)
     (when (eq (lui.layout:element-id node) :name)
       (let ((box (lui.layout:element-box node)))
         (format t "~&@@NAME=~D,~D~%"
                 (1+ (floor (lui.layout:box-x box)))
                 (1+ (floor (lui.layout:box-y box))))))
     (when (member (lui.layout:element-id node)
                   '((:page :controls) (:page :editing) (:page :layout))
                   :test #'equal)
       (let ((box (lui.layout:element-box node)))
         (format t "~&@@TAB-~A=~D,~D~%"
                 (second (lui.layout:element-id node))
                 (1+ (lui.terminal:cell-edge (lui.layout:box-x box)))
                 (1+ (lui.terminal:cell-edge (lui.layout:box-y box))))))
     (when (eq (lui.layout:element-id node) :reset)
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
    def __init__(self, cmd):
        self.master, self.slave = pty.openpty()
        self.before = termios.tcgetattr(self.slave)
        self.resize(90, 35)
        self.output = b""
        environment = os.environ.copy()
        software = Path.home() / "quicklisp/dists/quicklisp/software"
        environment["CL_SOURCE_REGISTRY"] = (
            f'(:source-registry (:directory "{ROOT}/") '
            f'(:tree "{software}/") :ignore-inherited-configuration)'
        )
        cache = Path(cmd[-1]).parent / "cache"
        environment["ASDF_OUTPUT_TRANSLATIONS"] = (
            f'(:output-translations ("{ROOT}/" "{cache}/") '
            ':inherit-configuration)'
        )
        self.process = subprocess.Popen(
            cmd, cwd=ROOT, stdin=self.slave, stdout=self.slave,
            stderr=self.slave, start_new_session=True, env=environment,
        )

    def resize(self, columns, rows):
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

    def until(self, needle, timeout=30):
        end = time.monotonic() + timeout
        while needle not in self.output and time.monotonic() < end:
            self.pump()
            if self.process.poll() is not None:
                self.pump()
                break
        assert needle in self.output, self.output.decode("utf-8", "replace")

    def send(self, data):
        os.write(self.master, data)
        self.pump(0.25)

    def restored(self):
        self.process.wait(timeout=10)
        self.pump()
        assert self.process.returncode == 0, self.output.decode("utf-8", "replace")
        assert termios.tcgetattr(self.slave) == self.before, "termios not restored"
        for sequence in (b"\x1b[?1049l", b"\x1b[?25h", b"\x1b[?1006l",
                         b"\x1b[?1003l"):
            assert sequence in self.output, f"Missing cleanup: {sequence!r}"

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
            self.process.wait()
        os.close(self.master)
        os.close(self.slave)


def last_frame(output):
    return output.rsplit(b"\x1b[?25l\x1b[H", 1)[-1]


def text_style(frame, text):
    end = frame.rfind(text)
    assert end >= 0, frame.decode("utf-8", "replace")
    foreground = background = None
    underline = False
    for match in re.finditer(rb"\x1b\[([0-9;]*)m", frame[:end]):
        codes = [int(code) for code in match[1].split(b";") if code]
        index = 0
        while index < len(codes):
            code = codes[index]
            if code == 0:
                foreground = background = None
                underline = False
            elif code in (4, 24):
                underline = code == 4
            elif code in (38, 48) and codes[index + 1:index + 2] == [2]:
                color = tuple(codes[index + 2:index + 5])
                if code == 38:
                    foreground = color
                else:
                    background = color
                index += 4
            index += 1
    return foreground, background, underline


def text_position(frame, text, last=True):
    """Locate a visible ASCII caption in the terminal's absolute-row output."""
    offset = frame.rfind(text) if last else frame.find(text)
    assert offset >= 0, frame.decode("utf-8", "replace")
    moves = list(re.finditer(rb"\x1b\[(\d+);(\d+)H", frame[:offset]))
    assert moves
    move = moves[-1]
    prefix = re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]", b"", frame[move.end():offset])
    return int(move[2]) + len(prefix.decode("utf-8")), int(move[1])


def exercise(lisp, path):
    terminal = Terminal(command(lisp, path))
    try:
        terminal.until(b"\x1b[?1049h", timeout=180)
        terminal.until(b"Common Lisp")
        terminal.until(b"\x1b[38;2;")
        assert b"\x1b[38;2;" in terminal.output
        assert b"\x1b[48;2;" in terminal.output
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
        frame = last_frame(terminal.output)
        assert b"[ Layout ]" in frame and b"[ Controls ]" not in frame
        assert text_style(frame, b"[ Layout ]")[1] == (37, 139, 255)
        # Hover is underline/accent text, distinct from the selected tab fill.
        x, y = tabs[b"EDITING"]
        terminal.send(f"\x1b[<35;{x};{y}M".encode())
        frame = last_frame(terminal.output)
        assert text_style(frame, b"  Editing  ") == (
            (37, 139, 255), (48, 48, 64), True)
        assert text_style(frame, b"[ Layout ]")[1] == (37, 139, 255)
        terminal.send(b"\x1b[<35;1;1M")
        frame = last_frame(terminal.output)
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
        terminal.until(b"Customize the active collection")
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
        terminal.until(b"(1)")
        checkpoint = len(terminal.output)
        terminal.send(b"\x1b[Z\r")
        assert b"[x] Enabled" in terminal.output[checkpoint:]
        checkpoint = len(terminal.output)
        terminal.send(b" ")
        assert b"[ ] Enabled" in terminal.output[checkpoint:]
        terminal.send(b"\t ")
        terminal.until(b"(2)")
        terminal.send(b"\r")
        terminal.until(b"(3)")
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
        terminal.until(b"Layout inspector")
        terminal.pump(0.2)
        # Unit-size rows expose the tab nodes without oversized disclosure pills.
        assert last_frame(terminal.output).count(b"TAB (PAGE") >= 5
        # Initial width30 in90columns: handle centered at x60 (zero based).
        terminal.send(b"\x1b[<0;61;4M")
        terminal.send(b"\x1b[<32;51;4M\x1b[<0;51;4m")
        terminal.send(b"\x1b[D")
        terminal.resize(100, 30)
        terminal.pump(0.4)
        frame = last_frame(terminal.output)
        assert b"Layout inspector" in frame
        assert b"\x1b[30;1H" in frame
        assert b"\x1b[31;1H" not in frame
        assert "│".encode() in frame
        assert b"\x1b[7m(" not in frame, "Resize rail repainted as a button"
        assert text_style(frame, "│".encode())[:2] == (
            (48, 48, 64), (37, 139, 255))
        # Select a real tree row, expand details, and scroll the long property
        # table without losing the fixed inspector controls.
        x, y = text_position(frame, b"PANEL WINDOW")
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        frame = last_frame(terminal.output)
        assert b"Geometry" in frame
        x, y = text_position(frame, b"Expand details")
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        frame = last_frame(terminal.output)
        assert b"Restore tree" in frame
        assert b"TAB (PAGE" not in frame
        for _ in range(16):
            if b"Input" in last_frame(terminal.output):
                break
            terminal.send(b"\x1b[<65;85;16M")
        frame = last_frame(terminal.output)
        assert b"Input" in frame, frame.decode("utf-8", "replace")
        x, y = text_position(frame, b"Restore tree")
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        frame = last_frame(terminal.output)
        assert b"Expand details" in frame
        assert b"PANEL WINDOW" in frame
        x, y = text_position(frame, b"PANEL WINDOW", last=False)
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        frame = last_frame(terminal.output)
        assert b"Geometry" not in frame
        x, y = text_position(frame, b"PANEL WINDOW", last=False)
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        frame = last_frame(terminal.output)
        x, y = text_position(frame, b"Expand details")
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        frame = last_frame(terminal.output)
        x, y = text_position(frame, b"Close details")
        terminal.send(f"\x1b[<0;{x};{y}M\x1b[<0;{x};{y}m".encode())
        frame = last_frame(terminal.output)
        assert b"Restore tree" not in frame
        assert b"Geometry" not in frame
        assert b"Layout inspector" in frame
        assert b"PANEL WINDOW" in frame
        terminal.send(b"\x11")
        terminal.until(b"@@DEBUG")
        terminal.restored()
        result = terminal.output.split(b"@@DEBUG", 1)[1]
        assert b"width=42.0" in result, result
        assert b"size=100x30" in result, result
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
            print(f"{lisp}: raw input, Unicode, inspector drag/keyboard resize "
                  "and restoration pass")


if __name__ == "__main__":
    main()
