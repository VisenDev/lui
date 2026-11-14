// Inline the runtime, adapter and application; no server or external fetches.
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

export async function packagePage(output, runtime, kind) {
  const adapter = await fs.readFile(path.join(runtime, 'miricl.js'), 'utf8');
  const bridge = await fs.readFile('scripts/miricl-web.js', 'utf8');
  const bytes = await fs.readFile(path.join(runtime, 'miricl-interpreter.wasm'));
  const bundle = await fs.readFile(`${output}/lui.wasm`);
  const start = kind === 'docs' ? '(%lui.docs:main :backend :web-miricl)'
    : '(%lui.example.demo:main)';
  const javascript = `${adapter}\n${bridge}
try {
  const decode = text => Uint8Array.from(atob(text), c => c.charCodeAt(0));
  const vm = await Miricl.instantiate(decode('${bytes.toString('base64')}'));
  vm.mountFile('/lui.wasm', decode('${bundle.toString('base64')}'));
  window.luiEvaluate = source => vm.evaluate(source, {eof:true}).output;
  window.luiEvaluate('(load "/lui.wasm") ${start}');
} catch (error) {
  document.body.textContent = 'Unable to start LUI: ' + error.message;
  throw error;
}
`;
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>LUI — MiriCL ${kind}</title><style>body{margin:0}</style></head>
<body><script type="module">${javascript.replace(/<\/script/gi, '<\\/script')}</script></body></html>`;
  await fs.writeFile(`${output}/index.html`, html);
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href)
  await packagePage(...process.argv.slice(2));
