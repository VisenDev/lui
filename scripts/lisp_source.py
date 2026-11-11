"""Locate Lisp forms without evaluating them; preserve source for lint tooling."""
from dataclasses import dataclass


@dataclass(frozen=True)
class Form:
    start: int
    end: int

    def text(self, source):
        return source[self.start:self.end]


def skip_space(source, start):
    while start < len(source):
        if source[start].isspace():
            start += 1
        elif source[start] == ';':
            newline = source.find('\n', start)
            start = len(source) if newline < 0 else newline + 1
        elif source.startswith('#|', start):
            depth = 1
            start += 2
            while depth:
                if start >= len(source):
                    raise ValueError('Unterminated block comment')
                if source.startswith('#|', start):
                    depth += 1
                    start += 2
                elif source.startswith('|#', start):
                    depth -= 1
                    start += 2
                else:
                    start += 1
        else:
            break
    return start


def form_at(source, start):
    start = skip_space(source, start)
    if start >= len(source):
        raise ValueError('Expected a Lisp form')
    char = source[start]
    if char == '(':
        end = start + 1
        while True:
            end = skip_space(source, end)
            if end >= len(source):
                raise ValueError('Unterminated list')
            if source[end] == ')':
                return Form(start, end + 1)
            end = form_at(source, end).end
    if char in "'`" or source.startswith(("#'", ',@'), start):
        prefix = 2 if source[start:start + 2] in ("#'", ',@') else 1
        return Form(start, form_at(source, start + prefix).end)
    if char == ',':
        return Form(start, form_at(source, start + 1).end)
    if source.startswith(('#+', '#-'), start):
        feature = form_at(source, start + 2)
        return Form(start, form_at(source, feature.end).end)
    if source.startswith('#(', start):
        return Form(start, form_at(source, start + 1).end)
    if source.startswith('#\\', start):
        end = start + 3  # The first character can itself be a delimiter.
        while end < len(source) and not source[end].isspace() and source[end] not in '()':
            end += 1
        return Form(start, end)
    quote = start + 2 if source.startswith('#j"', start) else start
    if source[quote] == '"':
        end = quote + 1
        while end < len(source):
            if source[end] == '\\':
                end += 2
            elif source[end] == '"':
                return Form(start, end + 1)
            else:
                end += 1
        raise ValueError('Unterminated string')
    end = start
    escaped_symbol = False
    while end < len(source):
        char = source[end]
        if char == '\\':
            end += 2
            continue
        if char == '|':
            escaped_symbol = not escaped_symbol
        elif not escaped_symbol and (char.isspace() or char in '();'):
            break
        end += 1
    if end == start:
        raise ValueError(f'Unexpected delimiter at {start}')
    return Form(start, end)


def children(source, form):
    """Yield the immediate children of a list, excluding delimiters/comments."""
    cursor = form.start + 1
    while (cursor := skip_space(source, cursor)) < form.end - 1:
        child = form_at(source, cursor)
        yield child
        cursor = child.end


def definitions(source):
    """Find definitions in executable forms, skipping strings and quoted data."""
    def visit(form):
        if source.startswith(('#+', '#-'), form.start):
            feature = form_at(source, form.start + 2)
            yield from visit(form_at(source, feature.end))
        elif source[form.start] == '(':
            parts = list(children(source, form))
            if not parts:
                return
            head = parts[0].text(source).lower()
            if head in ('quote', 'function'):
                return
            if head in ('fn', 'lui.fn:fn', 'defun', 'defmacro'):
                yield form, parts
                # Nested definitions are unusual but still need normalization.
                parts = parts[3:]
            for child in parts:
                yield from visit(child)

    cursor = 0
    while (cursor := skip_space(source, cursor)) < len(source):
        form = form_at(source, cursor)
        yield from visit(form)
        cursor = form.end
