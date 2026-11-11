// Run the core suite against MiriCL sources or the built application bundle.
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const runtime = path.resolve(process.env.MIRICL_RUNTIME ?? `${process.env.HOME}/clone/miricl`);
const {Miricl} = await import(pathToFileURL(path.join(runtime, 'miricl.js')));
const vm = await Miricl.instantiate(await fs.readFile(path.join(runtime, 'miricl.wasm')));
for (const directory of ['src', 'tests', 'examples']) {
  for (const file of await fs.readdir(directory)) {
    if (file.endsWith('.lisp')) {
      const source = `${directory}/${file}`;
      vm.mountFile(`/${source}`, await fs.readFile(source));
    }
  }
}
if (process.argv.includes('--bundle')) {
  vm.mountFile('/lui.wasm', await fs.readFile('build/miricl/lui.wasm'));
  vm.evaluate('(load "/lui.wasm") (pushnew :lui-test-bundle *features*)',
    {eof: true});
}
console.log(vm.evaluate('(load "/tests/run.lisp")', {eof: true}).output);
vm.close();
