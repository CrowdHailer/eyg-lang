import express from "express";

const servers = [];

export function serve(port, handler) {
  const app = express();
  app.use(express.raw({ type: "*/*", limit: "1mb" }));
  app.use(async (req, res) => {
    toResponse(handler(toRequest(req)), res);
  });
  const server = app.listen(port);
  const id = servers.length;
  servers.push(server);
  return id;
}

// addressing servers by server id should eventually be a general sending message to a process
export function stopServer(id) {
  const server = servers[id];
  server.close();
}

export async function receive(port, handler) {
  const app = express();
  const p = new Promise(function (resolve) {
    app.use(express.raw({ type: "*/*", limit: "1mb" }));
    app.use(async (req, res) => {
      const [response, maybeData] = handler(toRequest(req));
      // relies on there being no zero key in a none
      const data = maybeData["0"];
      if (data != undefined) {
        resolve(data);
      }
      toResponse(response, res);
    });
  });
  const server = app.listen(port, () => {
    console.log("listening", port);
  });
  const request = await p;
  server.close();
  return request;
}

function toRequest(req) {
  // https://stackoverflow.com/questions/10643981/how-to-get-the-unparsed-query-string-from-a-http-request-in-express
  const i = req.url.indexOf("?");
  const query = i > 0 ? req.url.substr(i + 1) : undefined;

  const reqbody = req.body instanceof Buffer ? req.body.toString() : "";
  return [
    req.method,
    req.protocol,
    req.headers.host,
    // path is always without query
    req.path,
    query,
    Object.entries(req.headers),
    reqbody,
  ];
}

function toResponse([status, headers, body], res) {
  res.status(status);
  headers.forEach(([k, v]) => {
    res.set(k, v);
  });
  res.send(body);
}
