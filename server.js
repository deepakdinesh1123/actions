const http = require('http');

const server = http.createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('Hello from the PReview MicroVM Test App!\n');
});

const port = process.env.PORT || 8080;
server.listen(port, () => {
    console.log(`Server listening on port ${port}`);
});
