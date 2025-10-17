# Simple Node.js application for testing
FROM node:18-alpine

WORKDIR /app

# Create a simple server
RUN echo 'const http = require("http");' > server.js && \
    echo 'const server = http.createServer((req, res) => {' >> server.js && \
    echo '  res.writeHead(200, {"Content-Type": "text/plain"});' >> server.js && \
    echo '  res.end("Hello from GitHub Actions + AWS ECS!");' >> server.js && \
    echo '});' >> server.js && \
    echo 'server.listen(80, () => console.log("Server running on port 80"));' >> server.js

EXPOSE 80

CMD ["node", "server.js"]
