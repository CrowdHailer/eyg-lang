import express from "express";

export function serve(port, handler) {
    const app = express();
    app.use(express.raw({ type: "*/*", limit: "1mb" }));
    app.use(async (req, res) => {
        // https://stackoverflow.com/questions/10643981/how-to-get-the-unparsed-query-string-from-a-http-request-in-express
        const i = req.url.indexOf('?');
        const query = i > 0 ? req.url.substr(i + 1): undefined;

        const reqbody = req.body instanceof Buffer ? req.body.toString() : "";
        console.log()
        const [status, headers, body] = handler(
            req.method,
            req.protocol,
            req.headers.host,
            // path is always without query
            req.path,
            query,
            // TODO headers
            reqbody,
        )
        res.send(body)
    })
    const server = app.listen(port)
    return server.close
}
