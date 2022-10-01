// import source from "./editor/public/saved.json" assert { type: "json" };
import * as Eyg from "./eyg/build/dev/javascript/eyg/dist/cli.mjs";
// console.log(source);
import express from "express";
import cors from "cors";

import url from "url";
const app = express();
const port = process.env.PORT || 8080;

// TODO Don't clash with proxy
// https://stackoverflow.com/a/18710277
app.use(cors());
app.use(express.raw({ type: "*/*" }));
let source = Eyg.load();
// console.log(source);
app.use((req, res) => {
  // TODO check host is cluster
  // TODO move into Eyg cluster fn, no where in this execution do we make a state available yet
  const clusterService =
    req.header("Host") == "localhost:5002" ||
    req.header("Host") === "cluster.web.petersaxton.uk";
  if (clusterService && req.path === "/deploy") {
    console.log("updated");
    source = Eyg.from_string(req.body.toString());
    res.send("{}");
    return;
  }

  console.log(req.method, req.path, req.body.toString());
  // TODO render which parameters are generic differently to unbound
  const result = Eyg.req(
    req.header("Host"),
    req.method,
    req.path,
    req.body.toString(),
    source
  );
  res.send(result);
});

app.listen(port, () => console.log(`HelloNode app listening on port ${port}!`));
