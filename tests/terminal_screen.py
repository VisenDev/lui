"""Streaming VT screen normalizer shared by the real PTY regressions."""
import codecs
import copy
import re
import unicodedata


def palette(index):
    basic = [(0, 0, 0), (205, 0, 0), (0, 205, 0), (205, 205, 0),
             (0, 0, 238), (205, 0, 205), (0, 205, 205), (229, 229, 229),
             (127, 127, 127), (255, 0, 0), (0, 255, 0), (255, 255, 0),
             (92, 92, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255)]
    if index < 16:
        return basic[index]
    if index < 232:
        value = index - 16
        levels = [0, 95, 135, 175, 215, 255]
        return tuple(levels[component] for component in (value // 36, value // 6 % 6, value % 6))
    return (8 + (index - 232) * 10,) * 3


class Screen:
    """Accumulate glyphs, styles and cursor state across arbitrary output chunks.

    Cell tuples contain text, foreground, background, underline, bold and italic.
    Wide glyph continuation cells contain an empty string. Default foreground and
    background remain distinct so reverse-video focus cannot disappear in a diff.
    """
    def __init__(self, columns, rows, autowrap=True):
        self.columns, self.rows = columns, rows
        self.foreground, self.background = "default-fg", "default-bg"
        self.underline = self.reverse = self.bold = self.italic = False
        self.cells = [self.blank_row() for _ in range(rows)]
        self.x = self.y = 0
        self.saved_cursor = (0, 0)
        self.cursor_visible = True
        self.cursor_shape = "default"
        self.cursor_blink = "default"
        self.autowrap = autowrap
        self.wrap_pending = False
        self._decoder = codecs.getincrementaldecoder("utf-8")()
        self._pending = ""

    def style(self):
        foreground, background = self.foreground, self.background
        if self.reverse:
            foreground, background = background, foreground
        return foreground, background, self.underline, self.bold, self.italic

    def blank(self):
        return (" ", *self.style())

    def blank_row(self):
        return [self.blank() for _ in range(self.columns)]

    def resize(self, columns, rows):
        old = self.cells
        self.columns, self.rows = columns, rows
        self.cells = [self.blank_row() for _ in range(rows)]
        for y in range(min(rows, len(old))):
            self.cells[y][:min(columns, len(old[y]))] = old[y][:columns]
        self.x, self.y = min(self.x, columns - 1), min(self.y, rows - 1)
        self.wrap_pending = False

    def snapshot(self):
        return copy.deepcopy(self)

    @property
    def text(self):
        return "\n".join("".join(cell[0] for cell in row) for row in self.cells)

    def decode(self, *_):
        return self.text

    def __contains__(self, text):
        return (text.decode() if isinstance(text, bytes) else text) in self.text

    def count(self, text):
        return self.text.count(text.decode() if isinstance(text, bytes) else text)

    def positions(self, text):
        text = text.decode() if isinstance(text, bytes) else text
        found = []
        for y, row in enumerate(self.cells):
            visible, columns = "", []
            for x, cell in enumerate(row):
                visible += cell[0]
                columns.extend([x] * len(cell[0]))
            for match in re.finditer(re.escape(text), visible):
                found.append((columns[match.start()], y))
        return found

    def newline(self):
        self.y += 1
        if self.y >= self.rows:
            self.cells.pop(0)
            self.cells.append(self.blank_row())
            self.y = self.rows - 1
        self.wrap_pending = False

    def rendition(self, codes):
        offset = 0
        while offset < len(codes):
            code = codes[offset]
            if code == 0:
                self.foreground, self.background = "default-fg", "default-bg"
                self.underline = self.reverse = self.bold = self.italic = False
            elif code in (4, 24):
                self.underline = code == 4
            elif code in (1, 2, 22):
                self.bold = code == 1
            elif code in (3, 23):
                self.italic = code == 3
            elif code in (7, 27):
                self.reverse = code == 7
            elif code in (39, 49):
                setattr(self, "foreground" if code == 39 else "background",
                        "default-fg" if code == 39 else "default-bg")
            elif code in (38, 48):
                mode = codes[offset + 1]
                if mode == 2:
                    color = tuple(codes[offset + 2:offset + 5])
                    offset += 4
                else:
                    assert mode == 5, codes
                    color = palette(codes[offset + 2])
                    offset += 2
                setattr(self, "foreground" if code == 38 else "background", color)
            elif 30 <= code <= 37 or 90 <= code <= 97:
                self.foreground = palette(code - 30 if code < 90 else code - 90 + 8)
            elif 40 <= code <= 47 or 100 <= code <= 107:
                self.background = palette(code - 40 if code < 100 else code - 100 + 8)
            else:
                assert code in (5, 25, 8, 28), code
            offset += 1

    def control(self, arguments, operation):
        if arguments.startswith("?"):
            modes = arguments[1:].split(";")
            if "1049" in modes and operation == "h":
                self.cells = [self.blank_row() for _ in range(self.rows)]
                self.x = self.y = 0
                self.wrap_pending = False
            if "7" in modes:
                self.autowrap = operation == "h"
            if "25" in modes:
                self.cursor_visible = operation == "h"
            if "12" in modes:
                self.cursor_blink = operation == "h"
            return
        codes = [int(code) if code else 0 for code in arguments.split(";")]
        number = codes[0] or 1
        if operation in ("H", "f"):
            self.y = (codes[0] or 1) - 1
            self.x = ((codes[1] if len(codes) > 1 else 1) or 1) - 1
        elif operation in "ABCD":
            self.y += number if operation == "B" else -number if operation == "A" else 0
            self.x += number if operation == "C" else -number if operation == "D" else 0
        elif operation in ("G", "`"):
            self.x = number - 1
        elif operation == "d":
            self.y = number - 1
        elif operation == "m":
            self.rendition(codes)
            return
        elif operation == "q":
            self.cursor_shape = codes[0]
            return
        elif operation == "J":
            mode = codes[0]
            if mode in (2, 3):
                self.cells = [self.blank_row() for _ in range(self.rows)]
            else:
                for y in range(self.rows):
                    for x in range(self.columns):
                        if (mode == 0 and (y, x) >= (self.y, self.x) or
                                mode == 1 and (y, x) <= (self.y, self.x)):
                            self.cells[y][x] = self.blank()
            return
        elif operation in ("K", "X"):
            start = 0 if operation == "K" and codes[0] in (1, 2) else self.x
            stop = self.x + 1 if operation == "K" and codes[0] == 1 else (
                min(self.columns, self.x + number) if operation == "X" else self.columns)
            self.cells[self.y][start:stop] = [self.blank()] * (stop - start)
            return
        elif operation == "s":
            self.saved_cursor = self.x, self.y
            return
        elif operation == "u":
            self.x, self.y = self.saved_cursor
        else:
            assert operation in ("h", "l", "t"), (arguments, operation)
            return
        self.x = min(max(self.x, 0), self.columns - 1)
        self.y = min(max(self.y, 0), self.rows - 1)
        self.wrap_pending = False

    def feed(self, output):
        text = self._pending + self._decoder.decode(output)
        index = 0
        while index < len(text):
            character = text[index]
            if character == "\x1b":
                rest = text[index:]
                if len(rest) < 2:
                    break
                if rest.startswith("\x1b["):
                    match = re.match(r"\x1b\[([0-?]*)([ -/]*)([@-~])", rest)
                    if not match:
                        assert not re.search(r"[@-~]", rest[2:]), repr(rest)
                        break
                    self.control(match[1], match[3])
                    index += len(match[0])
                elif rest.startswith("\x1b]"):
                    end = re.search(r"\x07|\x1b\\", rest)
                    if not end:
                        break
                    index += end.end()
                elif rest[1] in "()":
                    if len(rest) < 3:
                        break
                    assert rest[2] in "B0", repr(rest[:3])
                    index += 3
                else:
                    assert rest[1] in "=>78", repr(rest[:20])
                    if rest[1] == "7":
                        self.saved_cursor = self.x, self.y
                    elif rest[1] == "8":
                        self.x, self.y = self.saved_cursor
                    index += 2
                continue
            index += 1
            if character == "\n":
                self.newline()
                continue
            if character == "\r":
                self.x = 0
                self.wrap_pending = False
                continue
            if character == "\b":
                self.x = max(0, self.x - 1)
                continue
            if character == "\t":
                self.x = min((self.x // 8 + 1) * 8, self.columns - 1)
                continue
            if ord(character) < 32:
                continue
            width = 0 if unicodedata.category(character) in ("Mn", "Me", "Cf") else (
                2 if unicodedata.east_asian_width(character) in "WF" else 1)
            if width == 0:
                previous = self.x if self.wrap_pending else self.x - 1
                if 0 <= previous < self.columns:
                    while previous > 0 and not self.cells[self.y][previous][0]:
                        previous -= 1
                    cell = self.cells[self.y][previous]
                    self.cells[self.y][previous] = (cell[0] + character, *cell[1:])
                continue
            if self.wrap_pending:
                self.x = 0
                self.newline()
            self.cells[self.y][self.x] = (character, *self.style())
            if width == 2 and self.x + 1 < self.columns:
                self.cells[self.y][self.x + 1] = ("", *self.style())
            self.x += width
            if self.x >= self.columns:
                self.x = self.columns - 1
                self.wrap_pending = self.autowrap
        self._pending = text[index:]
        return self
