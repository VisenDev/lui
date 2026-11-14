// Test the compiled implementation without replacing it with source definitions.
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const runtime = path.resolve(process.env.MIRICL_RUNTIME ?? 'build/deps/miricl-runtime');
const {Miricl} = await import(pathToFileURL(path.join(runtime, 'miricl.js')));
const vm = await Miricl.instantiate(await fs.readFile(path.join(runtime, 'miricl.wasm')));
try {
  for (const directory of ['src', 'tests', 'examples'])
    for (const name of await fs.readdir(directory))
      if (name.endsWith('.lisp')) vm.mountFile(`/${directory}/${name}`,
        await fs.readFile(`${directory}/${name}`));
  vm.mountFile('/lui.wasm', await fs.readFile(process.argv[2] ?? 'build/docs-miricl/lui.wasm'));
  vm.evaluate('(load "/lui.wasm") (pushnew :lui-test-bundle *features*)', {eof:true});
  console.log(vm.evaluate('(load "/tests/run.lisp")', {eof:true}).output);
} finally { vm.close(); }
