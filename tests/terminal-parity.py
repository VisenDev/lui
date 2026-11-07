"""Compare historical and current terminal renderers and I/O through real PTYs.

Run python3 tests/terminal-parity.py [--baseline 16f79dd]. Both terminal source
files are extracted from the historical commit; current layout/widgets/demo are
shared. Streaming screen reconstruction compares complete visible cells/styles,
cursor and resize state, including output emitted as incremental patches.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

from terminal import ROOT, Terminal, command
from terminal_screen import Screen


def program(backend, toolkit, page):
    load = ('(asdf:load-system "lui/terminal")' if backend is None else
            f'(asdf:load-system "lui/core")\n(asdf:load-system "uncursed")\n'
            f'(load "{backend / "terminal.lisp"}")\n(load "{backend / "terminal-io.lisp"}")')
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
        terminal.until_visible(b"Frame rate: parity", timeout=180)
        terminal.pump(0.15)
        def capture(columns=90, rows=35):
            screen = terminal.frame()
            assert (screen.columns, screen.rows) == (columns, rows)
            result.append(screen)
        capture()
        start = len(terminal.output)
        initial_paint = len(terminal.output) - terminal.output.index(b"\x1b[?1049h")
        terminal.send(b"\x1b[<65;45;18M" if page == "scroll" else b"\x1b[1;2D\x1b[1;2D")
        if backend is None and page in ("controls", "editing"):
            assert len(terminal.output) - start < initial_paint // 2, "Cursor edit repainted a full frame"
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
        # Include initialization and cleanup in the cursor-mode invariants.
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
    parser.add_argument("--baseline", default="16f79dd")
    args = parser.parse_args()
    # Guard the normalizer's focus and right-margin behavior independently.
    reverse = Screen(2, 1).feed(b"\x1b[7mX")
    assert reverse.cells[0][0][1:3] == ("default-bg", "default-fg")
    wrapped = Screen(3, 2).feed(b"abcX")
    unwrapped = Screen(3, 2, autowrap=False).feed(b"abcX")
    assert wrapped.cells[1][0][0] == "X" and unwrapped.cells[0][2][0] == "X"
    assert Screen(3, 1).feed("abé".encode()).cells[0][2][0] == "é"
    # Escape and UTF-8 fragments must accumulate, rather than reset each patch.
    fragmented = Screen(5, 2)
    for chunk in (b"\x1b[2;", b"2H\x1b[38;2;1;2;3m", "界é".encode()[:1],
                  "界é".encode()[1:4], "界é".encode()[4:]):
        fragmented.feed(chunk)
    assert fragmented.cells[1][1] == ("界", (1, 2, 3), "default-bg", False, False, False)
    assert fragmented.cells[1][3][0] == "é"
    fragmented.feed(b"\x1b[1;1HX")
    assert fragmented.cells[1][1][0] == "界" and fragmented.cells[0][0][0] == "X"
    fragmented.resize(7, 3)
    assert fragmented.cells[1][3][0] == "é" and len(fragmented.cells[2]) == 7
    with tempfile.TemporaryDirectory(prefix="lui-terminal-parity-") as directory:
        directory = Path(directory)
        baseline = directory / "baseline"
        baseline.mkdir()
        for name in ("terminal.lisp", "terminal-io.lisp"):
            (baseline / name).write_bytes(subprocess.check_output(
                ["git", "show", f"{args.baseline}:src/{name}"], cwd=ROOT))
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
        print(f"Historical renderer and I/O comparison: {comparisons} snapshots, "
              f"{cells} styled cells match backend {args.baseline}")


if __name__ == "__main__":
    main()
