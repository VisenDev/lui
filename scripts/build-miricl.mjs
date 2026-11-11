// Build the same browser application with MiriCL's native Wasm application bundles.
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const runtime = path.resolve(process.env.MIRICL_RUNTIME ?? `${process.env.HOME}/clone/miricl`);
const output = 'build/miricl';
const mode = process.env.MIRICL_MODE ?? 'native';
if (!['native', 'interpreted'].includes(mode)) {
  throw new Error('MIRICL_MODE must be native or interpreted');
}
const sourceDirectory = path.resolve(process.env.MIRICL ?? runtime);
const license = await fs.readFile(path.join(sourceDirectory, 'LICENSE'));
const record = 'MiriCL runtime: https://github.com/ak-coram/miricl\n' +
  'License: LGPL-3.0-or-later; see MIRICL-LICENSE.\n';
const {Miricl} = await import(pathToFileURL(path.join(runtime, 'miricl.js')));
const bytes = await fs.readFile(path.join(runtime, 'miricl.wasm'));
const vm = await Miricl.instantiate(bytes);
const files = [
  'src/fn.lisp', 'src/web-js.lisp', 'src/layout.lisp', 'src/frame.lisp',
  'src/widgets.lisp', 'src/app.lisp', 'src/interaction.lisp',
  'src/glass.lisp', 'src/motif.lisp', 'src/desktop.lisp', 'src/garnet.lisp',
  'src/text-wrap.lisp', 'src/web-font.lisp', 'src/draw.lisp',
  'src/text-selection.lisp', 'src/paint-common.lisp', 'src/paint-glass.lisp',
  'src/paint-motif.lisp', 'src/paint-desktop.lisp', 'src/paint-garnet.lisp',
  'src/web-input.lisp', 'src/debug.lisp', 'src/web.lisp',
  'examples/seven-model.lisp', 'examples/seven-circles.lisp',
  'examples/seven-cells.lisp', 'examples/seven.lisp', 'examples/demo.lisp',
];
await fs.mkdir(output, {recursive: true});
const units = [];
for (const [index, file] of files.entries()) {
  console.log(`Compiling ${file}`);
  const source = `/${file}`;
  const target = `/unit-${index}.wasm`;
  vm.mountFile(source, await fs.readFile(file));
  vm.evaluate(`(multiple-value-bind (file warnings failure)
      (compile-file "${source}" :output-file "${target}")
    (declare (ignore warnings))
    (when (or failure (null file)) (error "Compilation failed: ${file}"))
    (load file))`, {eof: true});
  units.push(Buffer.from(await vm.readFile(target)).subarray(8));
}
// MiriCL bundles consist of a Wasm header and ordered FASL custom sections.
let bundle = Buffer.concat([Buffer.from([0,97,115,109,1,0,0,0]), ...units]);
vm.close();
if (mode === 'native') {
  console.log('Compiling native Wasm in a fresh runtime');
  // Later shadowing-imports change earlier symbols in the source-build VM.
  // Reconstruct each unit in order, before subsequent package reexports.
  const compiler = await Miricl.instantiate(bytes);
  compiler.mountFile('/portable.wasm', bundle);
  compiler.evaluate(`(miricl-compiler:compile-native-bundle
    "/portable.wasm" "/native.wasm" :load t)`, {eof: true});
  bundle = Buffer.from(await compiler.readFile('/native.wasm'));
  compiler.close();
}
// Verify load-time package and initialization dependencies in a fresh runtime.
const verifier = await Miricl.instantiate(bytes);
verifier.mountFile("/lui.wasm", bundle);
verifier.evaluate('(load "/lui.wasm") (values)', {eof: true});
if (mode === 'native') {
  verifier.evaluate(`(assert (eq miricl-compiler::*compiler-state* :cold))
    (dolist (function (list #'lui.web::draw-frame #'lui.layout:solve
                           #'lui.example:draw))
      (assert (plusp (miricl-compiler::compiler-primitive 26 function))))`,
    {eof: true});
}
verifier.close();
await fs.writeFile(`${output}/lui.wasm`, bundle);
await fs.copyFile(path.join(runtime, 'miricl.js'), `${output}/miricl.js`);
await fs.writeFile(`${output}/miricl.wasm`, bytes);
await fs.copyFile('examples/miricl.html', `${output}/index.html`);
await fs.writeFile(`${output}/MIRICL-LICENSE`, license);
await fs.writeFile(`${output}/MIRICL-NOTICE`, record);
console.log(`Wrote ${output}/index.html`);
