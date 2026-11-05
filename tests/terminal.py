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


def script(error=False):
    draw = """(let ((frames 0))
  (handler-case
      (lui:run (lambda ()
                 (lui.example:draw)
                 (when (> (incf frames) 1) (error "test draw failure")))
               :backend :terminal)
    (error () (format t "~&@@DRAW-ERROR~%"))))""" if error else """
(let ((context (lui:run #'lui.example:draw :backend :terminal)))
  (format t "~&@@RESULT name=~S volume=~,2F enabled=~S count=~D size=~Dx~D~%"
          lui.example::*name* lui.example::*volume* lui.example::*enabled*
          lui.example::*count* (lui.frame:context-width context)
          (lui.frame:context-height context)))"""
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
(load "examples/demo.lisp")
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
(let ((context (lui:run #'lui.example:draw :backend :terminal
                        :width 90 :height 35 :interactive nil)))
  (lui.layout:walk-elements
   (lui.frame:context-root context)
   (lambda (node)
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
        for sequence in (b"\x1b[?1049l", b"\x1b[?25h", b"\x1b[?1006l"):
            assert sequence in self.output, f"Missing cleanup: {sequence!r}"

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
            self.process.wait()
        os.close(self.master)
        os.close(self.slave)


def exercise(lisp, path):
    terminal = Terminal(command(lisp, path))
    try:
        terminal.until(b"\x1b[?1049h", timeout=180)
        terminal.until(b"Common Lisp")
        assert not termios.tcgetattr(terminal.slave)[3] & termios.ICANON
        terminal.send(b"\t\x01Terminal")
        # UTF-8 and CSI input may arrive in separate reads.
        terminal.send("界".encode("utf-8")[:1])
        terminal.send("界".encode("utf-8")[1:])
        terminal.send(b"\x1b[")
        terminal.send(b"D\x7f")
        terminal.send(b"l")
        # Backspace before the final wide character, then replace that character.
        terminal.send(b"\x1b[F\x7f!")
        terminal.send(b"\t\x1b[C\t \t\r")
        terminal.until(b"(1)")
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
            print(f"{lisp}: raw input, mouse, Unicode, resize and restoration pass")


if __name__ == "__main__":
    main()
