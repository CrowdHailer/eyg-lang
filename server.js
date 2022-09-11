import source from "./editor/public/saved.json" assert { type: "json" };
import * as Eyg from "./eyg/build/dev/javascript/eyg/dist/cli.mjs";
console.log(source);
import express from "express";
const app = express();
const port = process.env.PORT || 8080;

app.get("/", (req, res) => {
  const greeting = "<h1>Hello From Node on Fly!</h1>";
  res.send(greeting);
});
app.get("/:program", (req, res) => {
  const program = req.params["program"];
  res.send(JSON.stringify(Eyg.run([program])));
});

app.listen(port, () => console.log(`HelloNode app listening on port ${port}!`));
