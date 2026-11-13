"""Run strict Mallet, metrics and documentation checks on normalized FN code."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

from lisp_source import children, definitions

ROOT = Path(__file__).resolve().parents[1]


def ordinary_parameters(source, parameters):
    result = []
    mode = '&required'
    for parameter in children(source, parameters):
        text = parameter.text(source)
        if text.lower() in ('&optional', '&key', '&rest', '&aux'):
            mode = text.lower()
            result.append(text)
            continue
        if not text.startswith('('):
            result.append(text)
            continue
        parts = list(children(source, parameter))
        if mode in ('&optional', '&key', '&aux'):
            head = parts[0]
            name = (next(children(source, head)).text(source)
                    if head.text(source).startswith('(') else head.text(source))
            result.append('(' + ' '.join([name] + [p.text(source) for p in parts[1:]]) + ')')
        else:
            result.append(parts[0].text(source))
    return '(' + ' '.join(result) + ')'


def normalize(source):
    """Desugar FN headers and typed parameters without moving body line numbers."""
    for form, parts in reversed(list(definitions(source))):
        if parts[0].text(source).lower() not in ('fn', '%lui.fn:fn'):
            continue
        name = parts[1]
        if name.text(source).startswith('('):
            name = next(children(source, name))
        end = parts[2].end
        header = '(defun ' + name.text(source) + ' ' + ordinary_parameters(source, parts[2])
        line_count = source[form.start:end].count('\n')
        # Defaults can contain newlines; keep them and pad only removed lines.
        header += '\n' * (line_count - header.count('\n'))
        source = source[:form.start] + header + source[end:]
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default='build/logs/mallet-normalized.json')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='lui-lint-') as directory:
        target = Path(directory)
        for source in sorted((ROOT / 'src').glob('*.lisp')):
            (target / source.name).write_text(normalize(source.read_text()))
        result = subprocess.run([
            'mallet', str(target), '--strict', '--disable', 'no-package-use',
            '--enable', 'cyclomatic-complexity', '--enable', 'function-length',
            '--enable', 'missing-docstring', '--fail-on', 'info', '--format', 'json'],
            capture_output=True, text=True)
        if result.returncode not in (0, 1):
            raise SystemExit(result.stderr or result.stdout)
        report = json.loads(result.stdout)
        for file in report:
            file['file'] = 'src/' + Path(file['file']).name
            for item in file['violations']:
                print(f"{file['file']}:{item['line']}: {item['severity']}: "
                      f"{item['message']} [{item['rule']}]")
        output = ROOT / args.output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, indent=2) + '\n')
        print(result.stderr.strip())
        return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
