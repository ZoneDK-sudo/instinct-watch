// Tiny static server for previewing the dashboard folder locally.
import http from 'http';
import fs from 'fs';
import path from 'path';
const dir = path.resolve(process.argv[2] || '../dashboard');
const port = +(process.argv[3] || 5179);
const types = { '.html': 'text/html; charset=utf-8', '.json': 'application/json' };
http.createServer((req, res) => {
  const p = path.join(dir, decodeURIComponent(req.url.split('?')[0]) === '/' ? 'index.html' : decodeURIComponent(req.url.split('?')[0]));
  if (!p.startsWith(dir) || !fs.existsSync(p)) { res.writeHead(404); return res.end(); }
  const body = fs.readFileSync(p);
  res.writeHead(200, { 'content-type': types[path.extname(p)] || 'application/octet-stream' });
  // mimic the publish skeleton so the preview matches
  res.end(p.endsWith('.html') ? '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><style>body{margin:0;font:14px system-ui}[hidden]{display:none!important}</style>' + body : body);
}).listen(port, () => console.log('serving', dir, 'on', port));
