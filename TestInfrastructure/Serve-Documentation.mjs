import { createReadStream, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, isAbsolute, join, normalize, relative, resolve, sep } from 'node:path';

const root = resolve('docs');
const contentTypes = new Map([
  ['.css', 'text/css; charset=utf-8'],
  ['.html', 'text/html; charset=utf-8'],
  ['.jpg', 'image/jpeg'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
]);

createServer((request, response) => {
  let pathname;
  try {
    pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
  } catch {
    response.writeHead(400).end('Bad request');
    return;
  }

  const requestedPath = pathname === '/' ? '/index.html' : pathname;
  const filePath = normalize(join(root, requestedPath));
  const relativePath = relative(root, filePath);
  if (relativePath === '..' || relativePath.startsWith(`..${sep}`) || isAbsolute(relativePath)) {
    response.writeHead(403).end('Forbidden');
    return;
  }

  try {
    const file = statSync(filePath);
    if (!file.isFile()) throw new Error('Not a file');
    response.writeHead(200, {
      'Content-Length': file.size,
      'Content-Type': contentTypes.get(extname(filePath)) ?? 'application/octet-stream',
    });
    createReadStream(filePath).pipe(response);
  } catch {
    response.writeHead(404).end('Not found');
  }
}).listen(4173, '127.0.0.1');
