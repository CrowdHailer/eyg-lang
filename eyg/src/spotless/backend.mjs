import express from "express";

const app = express();
app.use(express.raw({ type: "*/*", limit: "1mb" }));
app.use(async (req, res) => {
    console.log(req)
    res.send(Buffer.from("hello"));
    // toResponse(await handler(toRequest(req)), res);
});
const server = app.listen(8081);
console.log("serving on port: ", 8081)