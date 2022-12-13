import express from "express";
import cors from "cors";

import url from "url";
const app = express();
const port = process.env.PORT || 8899;

app.use(cors());
app.use(express.raw({ type: "*/*", limit: "1mb" }));

export function serve(handler) {
  app.use((req, res) => {
    console.log("bob!!");
    console.log(req.path);
    // console.log(req.body.toString());
    const result = handler(req.path);
    console.log("result", result);
    res.send(result);
  });

  app.listen(port, () =>
    console.log(`HelloNode app listening on port ${port}!`)
  );
  console.log("noop");
}
