const http = require('http');
const fs = require('fs');
const path = require('path');
const root = process.cwd();
const server = http.createServer((req, res) => {
  let reqPath = req.url.split('?')[0].split('#')[0];
  if (reqPath === '/') reqPath = '/index.html';
  const filePath = path.join(root, reqPath.replace(/^\//, ''));
  fs.readFile(filePath, (err, data) => {
    if (err) { res.statusCode = 404; res.end('not found'); return; }
    const ext = path.extname(filePath).toLowerCase();
    const type = ext === '.html' ? 'text/html' : ext === '.jpg' || ext === '.jpeg' ? 'image/jpeg' : 'text/plain';
    res.setHeader('Content-Type', type);
    res.end(data);
  });
});
server.listen(3000, '127.0.0.1', () => console.log('vetpro server on 3000'));
setInterval(() => {}, 1 << 30);
