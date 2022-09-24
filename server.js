import source from "./editor/public/saved.json" assert { type: "json" };
import * as Eyg from "./eyg/build/dev/javascript/eyg/dist/cli.mjs";
// console.log(source);
import express from "express";
import url from "url";
const app = express();
const port = process.env.PORT || 8080;

// TODO set up logs
// TODO Don't clash with proxy
// https://stackoverflow.com/a/18710277
app.use(express.raw({ type: "*/*" }));
app.use((req, res) => {
  console.log(req.method, req.path, req.body.toString());
  // TODO render which parameters are generic differently to unbound
  const result = Eyg.req(
    req.header("Host"),
    req.method,
    req.path,
    req.body.toString()
  );
  console.log(result);
  res.send(result);
});
// app.get("/:program", (req, res) => {
//   const program = req.params["program"];
//   res.send(JSON.stringify());
// });

app.listen(port, () => console.log(`HelloNode app listening on port ${port}!`));
