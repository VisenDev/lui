import http from 'node:http';
import { readFile, realpath, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = await realpath(fileURLToPath(new URL('..', import.meta.url)));
const port = Number(process.env.PORT ?? 8000);
const example = process.env.LUI_EXAMPLE ?? 'demo';
if (!Number.isInteger(port) || port < 0 || port > 65535) {
  throw new Error('PORT must be an integer between 0 and 65535.');
}
if (!['demo', 'showcase'].includes(example)) {
  throw new Error('LUI_EXAMPLE must be demo or showcase.');
}

const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
};

const server = http.createServer(async (request, response) => {
  const fail = (status, message) => {
    response.writeHead(status, { 'Content-Type': 'text/plain; charset=utf-8' });
    response.end(request.method === 'HEAD' ? undefined : `${message}\n`);
  };
  if (!['GET', 'HEAD'].includes(request.method)) {
    response.setHeader('Allow', 'GET, HEAD');
    fail(405, 'Method not allowed');
    return;
  }

  let pathname;
  try {
    // Decode before checking segments; URL normalization would hide traversal.
    pathname = decodeURIComponent(request.url.split('?')[0]);
  } catch {
    fail(400, 'Invalid request path');
    return;
  }
  if (!pathname.startsWith('/') || pathname.includes('\0')) {
    fail(400, 'Invalid request path');
    return;
  }
  if (pathname.includes('\\') || pathname.split('/').includes('..')) {
    fail(403, 'Forbidden');
    return;
  }

  try {
    const filename = await realpath(path.resolve(root, `.${pathname}`));
    // Check the resolved path too, so symlinks cannot escape the repository.
    if (filename !== root && !filename.startsWith(`${root}${path.sep}`)) {
      fail(403, 'Forbidden');
      return;
    }
    const info = await stat(filename);
    if (!info.isFile()) {
      fail(404, 'Not found');
      return;
    }
    const data = request.method === 'HEAD' ? undefined : await readFile(filename);
    response.writeHead(200, {
      'Content-Type': types[path.extname(filename)] ?? 'application/octet-stream',
      'Content-Length': data?.length ?? info.size,
      'Cache-Control': 'no-store',
    });
    response.end(data);
  } catch (error) {
    fail(['ENOENT', 'ENOTDIR'].includes(error.code) ? 404 : 500,
         ['ENOENT', 'ENOTDIR'].includes(error.code) ? 'Not found' : 'Server error');
  }
});

server.on('error', error => {
  console.error(`Cannot serve LUI: ${error.message}`);
  process.exitCode = 1;
});
server.listen(port, '127.0.0.1', () => {
  const address = server.address();
  console.log(`LUI ${example}: http://127.0.0.1:${address.port}` +
              `/examples/web.html?example=${example}`);
});
