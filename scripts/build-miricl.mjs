// Build native MiriCL bundles and a self-contained, offline browser page.
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const runtime = path.resolve(process.env.MIRICL_RUNTIME ?? `${process.env.HOME}/clone/miricl`);
const source = path.resolve(process.env.MIRICL ?? `${process.env.HOME}/clone/miricl`);
const kind = process.argv[2] ?? 'gallery';
if (!['gallery', 'docs'].includes(kind)) throw new Error('Expected gallery or docs');
const output = kind === 'docs' ? 'build/docs-miricl' : 'build/miricl';
await fs.mkdir(output, {recursive: true});
const {Miricl} = await import(pathToFileURL(path.join(runtime, 'miricl.js')));
const bytes = await fs.readFile(path.join(runtime, 'miricl.wasm'));
const files = [
  'src/01-fn.lisp',
  'src/02-conditions.lisp',
  'src/03-text.lisp',
  'src/backend-miricl.lisp',
  'src/04-layout.lisp',
  'src/05-frame.lisp',
  'src/06-widgets.lisp',
  'src/07-palette.lisp',
  'src/08-toolkit.lisp',
  'src/09-lui.lisp',
  'src/10-interaction.lisp',
  'src/11-glass.lisp',
  'src/12-motif.lisp',
  'src/13-macos.lisp',
  'src/14-qt.lisp',
  'src/15-garnet.lisp',
  'src/16-debug.lisp',
];
files.push('src/backend-common.lisp', ...['glass', 'motif', 'macos', 'qt', 'garnet']
  .map(name => `src/paint-${name}.lisp`), 'src/backend-common-web.lisp',
  ...['seven-model', 'seven-circles', 'seven-cells', 'seven', 'demo']
    .map(name => `examples/${name}.lisp`));
if (kind === 'docs') files.push('examples/docs.lisp', 'build/docs-data.lisp');
// Match the ECL application's declared compilation policy.
const policy = "(proclaim '(optimize (speed 3) (debug 0) (space 0) (safety 2)))";
const vm = await Miricl.instantiate(bytes);
const units = [];
try {
  vm.evaluate(policy, {eof:true});
  vm.evaluate('(pushnew :lui-miricl-web *features*)', {eof: true});
  for (const [index, file] of files.entries()) {
    console.log(`Compiling ${file}`);
    let input = `/${file}`;
    const target = `/unit-${index}.wasm`;
    vm.mountFile(input, await fs.readFile(file));
    if (['src/05-frame.lisp', 'src/backend-common.lisp',
         'src/backend-common-web.lisp'].includes(file)) {
      const prepared = `/prepared-${index}.lisp`;
      vm.evaluate(`(%lui.miricl.web.reader:prepare-source "${input}" "${prepared}" ${file === 'src/05-frame.lisp' ? 'nil' : 't'})`, {eof: true});
      input = prepared;
    }
    vm.evaluate(`(multiple-value-bind (file warnings failure)
        (compile-file "${input}" :output-file "${target}")
      (declare (ignore warnings))
      (when (or failure (null file)) (error "Compilation failed: ${file}"))
      (load file))`, {eof: true});
    units.push(Buffer.from(await vm.readFile(target)).subarray(8));
    if (file === 'src/backend-miricl.lisp') {
      vm.mountFile('/reader.lisp', await fs.readFile('scripts/miricl-web-reader.lisp'));
      vm.evaluate('(load "/reader.lisp")', {eof: true});
    }
  }
} finally { vm.close(); }
let bundle = Buffer.concat([Buffer.from([0,97,115,109,1,0,0,0]), ...units]);
const compiler = await Miricl.instantiate(bytes);
try {
  console.log('Compiling native Wasm in a fresh runtime');
  compiler.evaluate(policy, {eof:true});
  compiler.mountFile('/portable.wasm', bundle);
  compiler.evaluate('(miricl-compiler:compile-native-bundle "/portable.wasm" "/native.wasm" :load t)', {eof: true});
  bundle = Buffer.from(await compiler.readFile('/native.wasm'));
} finally { compiler.close(); }
const verifier = await Miricl.instantiate(bytes);
try {
  const state = verifier.evaluate('miricl-compiler::*compiler-state*').output.trim();
  verifier.mountFile('/lui.wasm', bundle);
  verifier.evaluate('(load "/lui.wasm") (values)', {eof: true});
  verifier.evaluate(`(assert (eq miricl-compiler::*compiler-state* ${state}))
    (dolist (function (list #'lui.web:mount #'%lui.layout:solve
                           #'%lui.example.demo:draw))
      (assert (plusp (miricl-compiler::compiler-primitive 26 function))))`, {eof: true});
} finally { verifier.close(); }
await fs.writeFile(`${output}/lui.wasm`, bundle);
// The delivered page needs only the interpreter, not the build compiler.
const delivery = await Miricl.instantiate(
  await fs.readFile(path.join(runtime, 'miricl-interpreter.wasm')));
try {
  delivery.mountFile('/lui.wasm', bundle);
  delivery.evaluate('(load "/lui.wasm") (values)', {eof:true});
} finally { delivery.close(); }
const {packagePage} = await import('./package-miricl.mjs');
await packagePage(output, runtime, kind);
await fs.copyFile(path.join(source, 'LICENSE'), `${output}/MIRICL-LICENSE`);
await fs.writeFile(`${output}/MIRICL-NOTICE`, 'MiriCL: https://github.com/ak-coram/miricl\nLGPL-3.0-or-later; see MIRICL-LICENSE.\n');
console.log(`Wrote ${output}/index.html`);
