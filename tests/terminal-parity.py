"""Compare baseline and uncursed terminal cells/styles through real PTYs.

Run python3 tests/terminal-parity.py [--baseline 561516f]. The baseline backend
runs against the current shared renderer, isolating terminal transport changes.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile
import unicodedata

from terminal import ROOT, Terminal, command, last_frame


class Screen:
    """Normalize the cursor/SGR subset emitted by both full-frame backends."""
    def __init__(self, columns, rows, autowrap=True):
        self.columns, self.rows = columns, rows
        self.cells = [[(" ", "default-fg", "default-bg", False, False, False) for _ in range(columns)]
                      for _ in range(rows)]
        self.x = self.y = 0
        self.foreground, self.background = "default-fg", "default-bg"
        self.underline = self.reverse = self.bold = self.italic = False
        self.cursor_visible = False
        self.cursor_shape = "default"
        self.autowrap = autowrap
        self.wrap_pending = False

    def feed(self, output):
        text = output.decode("utf-8")
        index = 0
        while index < len(text):
            character = text[index]
            if character == "\x1b":
                if text.startswith("\x1b(B", index):
                    index += 3
                    continue
                match = re.match(r"\x1b\[([0-?]*)([ -/]*)([@-~])", text[index:])
                assert match, repr(text[index:index + 30])
                arguments, _, operation = match.groups()
                index += len(match[0])
                if arguments.startswith("?"):
                    if "7" in arguments[1:].split(";"):
                        self.autowrap = operation == "h"
                    if "25" in arguments[1:].split(";"):
                        self.cursor_visible = operation == "h"
                    continue
                codes = [int(code) if code else 0 for code in arguments.split(";")]
                if operation in ("H", "f"):
                    self.y = (codes[0] or 1) - 1
                    self.x = ((codes[1] if len(codes) > 1 else 1) or 1) - 1
                    self.wrap_pending = False
                elif operation == "m":
                    offset = 0
                    while offset < len(codes):
                        code = codes[offset]
                        if code == 0:
                            self.foreground, self.background = "default-fg", "default-bg"
                            self.underline = self.reverse = self.bold = self.italic = False
                        elif code in (4, 24):
                            self.underline = code == 4
                        elif code in (1, 22):
                            self.bold = code == 1
                        elif code in (3, 23):
                            self.italic = code == 3
                        elif code in (7, 27):
                            self.reverse = code == 7
                        elif code in (39, 49):
                            setattr(self, "foreground" if code == 39 else "background", "default-fg" if code == 39 else "default-bg")
                        elif code in (38, 48):
                            assert codes[offset + 1] == 2
                            color = tuple(codes[offset + 2:offset + 5])
                            setattr(self, "foreground" if code == 38 else "background", color)
                            offset += 4
                        else:
                            raise AssertionError(code)
                        offset += 1
                elif operation == "q":
                    self.cursor_shape = codes[0]
                else:
                    raise AssertionError(operation)
                continue
            index += 1
            if character == "\n":
                self.y += 1
                continue
            if character == "\r":
                self.x = 0
                continue
            width = 0 if unicodedata.combining(character) else (
                2 if unicodedata.east_asian_width(character) in "WF" else 1)
            if width == 0:
                previous = self.x if self.wrap_pending else self.x - 1
                if 0 <= self.y < self.rows and 0 <= previous < self.columns:
                    while previous > 0 and not self.cells[self.y][previous][0]:
                        previous -= 1
                    cell = self.cells[self.y][previous]
                    self.cells[self.y][previous] = (cell[0] + character, *cell[1:])
                continue
            if self.wrap_pending:
                self.x = 0
                self.y += 1
                self.wrap_pending = False
            foreground, background = self.foreground, self.background
            if self.reverse:
                foreground, background = background, foreground
            if 0 <= self.y < self.rows and 0 <= self.x < self.columns:
                self.cells[self.y][self.x] = (character, foreground, background, self.underline, self.bold, self.italic)
                if width == 2 and self.x + 1 < self.columns:
                    self.cells[self.y][self.x + 1] = ("", foreground, background, self.underline, self.bold, self.italic)
            self.x += width
            if self.x >= self.columns:
                self.x = self.columns - 1
                self.wrap_pending = self.autowrap
        return self


def program(backend, toolkit, page):
    load = ('(asdf:load-system "lui/terminal")' if backend is None else
            f'(asdf:load-system "lui/core")\n(asdf:load-system "cffi")\n(load "{backend}")')
    focus = {"controls": "name", "editing": "editor", "layout": "split", "scroll": "filter", "styles": "toolkit"}[page]
    return f'''(load "scripts/setup.lisp")
{load}
(asdf:load-system "lui/demo")
(setf (symbol-function 'lui.frame::frame-rate-label)
      (lambda (state) (declare (ignore state)) "Frame rate: parity"))
(let ((gallery (lui.example:make-gallery :toolkit :{toolkit} :page :{page}
                                       :name "A界é 🦊" :editor "Unicode 界é 🦊 clipped text"))
      (first t))
  (lui:run (lambda ()
             (lui.example:draw gallery)
             (when first
               (setf first nil
                     (lui.frame:context-focus lui.frame:*context*) :{focus}
                     (lui.frame:context-focus-visible-p lui.frame:*context*) t)))
           :backend :terminal))
'''


def snapshots(path, backend, toolkit, page, term="xterm-direct"):
    path.write_text(program(backend, toolkit, page), encoding="utf-8")
    terminal = Terminal(command("sbcl", path), term=term)
    result = []
    try:
        terminal.until(b"Frame rate: parity", timeout=180)
        terminal.pump(0.15)
        def capture(columns=90, rows=35):
            autowrap = True  # Fresh xterm-compatible PTYs start with DECAWM set.
            for mode in re.finditer(rb"\x1b\[\?([0-9;]+)([hl])", terminal.output):
                if b"7" in mode[1].split(b";"):
                    autowrap = mode[2] == b"h"
            result.append(Screen(columns, rows, autowrap).feed(last_frame(terminal.output)))
        capture()
        terminal.send(b"\x1b[<65;45;18M" if page == "scroll" else b"\x1b[1;2D\x1b[1;2D")
        capture()
        terminal.send(b"\t")
        capture()
        terminal.resize(50, 20)
        terminal.pump(0.3)
        capture(50, 20)
        terminal.resize(101, 41)
        terminal.pump(0.3)
        capture(101, 41)
        terminal.send(b"\x11")
        terminal.process.wait(timeout=10)
        assert terminal.process.returncode == 0
        terminal.pump()
        # Include initialization and cleanup, which last_frame deliberately omits.
        assert not re.search(rb"\x1b\[[0-9]* q", terminal.output), "Cursor shape changed"
        for mode in re.finditer(rb"\x1b\[\?([0-9;]+)[hl]", terminal.output):
            assert b"12" not in mode[1].split(b";"), "Cursor blink mode changed"
    finally:
        terminal.close()
    if page == "scroll":
        assert result[0].cells != result[1].cells, "Wheel input did not scroll visible cells"
    if page in ("controls", "editing"):
        assert (result[0].x, result[0].y) != (result[1].x, result[1].y), "Shift selection did not move the field cursor"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", default="561516f")
    args = parser.parse_args()
    # Guard the normalizer's focus and right-margin behavior independently.
    reverse = Screen(2, 1).feed(b"\x1b[7mX")
    assert reverse.cells[0][0][1:3] == ("default-bg", "default-fg")
    wrapped = Screen(3, 2).feed(b"abcX")
    unwrapped = Screen(3, 2, autowrap=False).feed(b"abcX")
    assert wrapped.cells[1][0][0] == "X" and unwrapped.cells[0][2][0] == "X"
    assert Screen(3, 1).feed("abé".encode()).cells[0][2][0] == "é"
    with tempfile.TemporaryDirectory(prefix="lui-terminal-parity-") as directory:
        directory = Path(directory)
        baseline = directory / "baseline.lisp"
        baseline.write_bytes(subprocess.check_output(
            ["git", "show", f"{args.baseline}:src/terminal-io.lisp"], cwd=ROOT))
        path = directory / "run.lisp"
        comparisons = cells = 0
        cases = [(toolkit, page, "xterm-direct")
                 for toolkit in ("glass", "motif", "garnet")
                 for page in ("controls", "editing", "layout", "scroll", "styles")]
        cases += [(toolkit, "controls", "xterm-256color")
                  for toolkit in ("glass", "motif", "garnet")]
        for toolkit, page, term in cases:
            before = snapshots(path, baseline, toolkit, page, term)
            after = snapshots(path, None, toolkit, page, term)
            for phase, (expected, actual) in enumerate(zip(before, after)):
                differences = [(x, y, left, right)
                               for y, (row1, row2) in enumerate(zip(expected.cells, actual.cells))
                               for x, (left, right) in enumerate(zip(row1, row2)) if left != right]
                assert not differences, (toolkit, page, phase, differences[:12])
                assert expected.cursor_visible == actual.cursor_visible, (toolkit, page, phase, "cursor visibility")
                assert expected.cursor_shape == actual.cursor_shape, (toolkit, page, phase, "cursor shape")
                if expected.cursor_visible:
                    assert (expected.x, expected.y) == (actual.x, actual.y), (toolkit, page, phase, "cursor position")
                comparisons += 1
                cells += expected.rows * expected.columns
            print(f"{term} {toolkit}/{page}: five cell/style/focus snapshots match", flush=True)
        print(f"{comparisons} snapshots, {cells} styled cells match {args.baseline}")


if __name__ == "__main__":
    main()
