// import express from "express";
console.log(process.cwd());
import express from "express";
import cors from "cors";

import url from "url";
const app = express();
const port = process.env.PORT || 8899;

app.use(cors());
app.use(express.raw({ type: "*/*", limit: "1mb" }));
// express.static.mime.define({ "application/json": ["mjs"] });
app.use(
  "/src",
  // (req, resp, next) => {
  //   console.log("nooooooooooooo", req.path.endsWith(".mjs"));
  //   res.setHeader("content-type", "*");
  //   next();
  // },
  express.static("build/dev/javascript", {
    setHeaders: function (res, path, stat) {
      // if file is a .xml file, then set content-type
      console.log(path);
      if (path.endsWith(".mjs")) {
        res.setHeader("Content-Type", "application/javascript");
      }
    },
  })
);

const page = `
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Editor</title>
</head>
<body>
<h1>Yep</h1>

<script type="module">
  import * as core from "https://cdn.skypack.dev/solid-js";
  import {render} from "https://cdn.skypack.dev/solid-js/web";
  import h from "https://cdn.skypack.dev/solid-js/h";
  window.Solid = {
    core,
    h,
  }
  import {app} from "/src/eyg/workspace.mjs"
  render(app, document.body)
</script>
</html>
`;


// TODO solid example does have h defined

export function serve(handler) {
  console.log(process.cwd());
  app.use((req, res) => {
    if (req.header("host") == "localhost:8899") {
      res.send(page);
    } else {
      console.log("bob!!");
      console.log(req.hostname);
      // console.log(req.body.toString());
      const result = handler(req.path);
      console.log("result", result);
      res.send(result);
    }
  });

  app.listen(port, () =>
    console.log(`HelloNode app listening on port ${port}!`)
  );
  console.log("noop");
}

// TODO gleam run --watch look at JS source files and gleam source files
// cant use https in gleam copy the lustre approach
// use solid
// simple js page
// use my HTML
// express static
