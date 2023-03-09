import express from "express";
import cors from "cors";

import url from "url";
const app = express();
const port = process.env.PORT || 5000;

app.use(cors());
app.use(express.raw({ type: "*/*", limit: "1mb" }));
// express.static.mime.define({ "application/json": ["mjs"] });
app.use(
  "/src",
  express.static("build/dev/javascript", {
    setHeaders: function (res, path, stat) {
      // if file is a .xml file, then set content-type
      if (path.endsWith(".mjs") || path.endsWith(".js")) {
        res.setHeader("Content-Type", "application/javascript");
      }
    },
  })
);
app.use(
  "/public",
  express.static("public", {
    setHeaders: function (res, path, stat) {
      // if file is a .xml file, then set content-type
      if (path.endsWith(".mjs") || path.endsWith(".js")) {
        res.setHeader("Content-Type", "application/javascript");
      }
    },
  })
);
app.use(
  "/build",
  express.static("build/dev/javascript", {
    setHeaders: function (res, path, stat) {
      // if file is a .xml file, then set content-type
      if (path.endsWith(".mjs") || path.endsWith(".js")) {
        res.setHeader("Content-Type", "application/javascript");
      }
    },
  })
);
app.use(
  "/saved",
  express.static("saved")
);


const lustre = `
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<link href="https://unpkg.com/tailwindcss@2.2.11/dist/tailwind.min.css" rel="stylesheet" />
<link href="/public/layout.css" rel="stylesheet" />
<script src="https://unpkg.com/react@18/umd/react.development.js" crossorigin></script>
<script src="https://unpkg.com/react-dom@18/umd/react-dom.development.js" crossorigin></script>
<title>Atelier</title>
</head>
<body>
  <div id="app" class="screen"></div>
  <script src="/public/bundle.js"></script>
</html>
`;

export function serve(handler, saver) {
  app.use((req, res) => {
    let host = req.header("host");
    if (host == "localhost:5000" || host == "source.web.petersaxton.uk") {
      if (req.path == "/save") {
        let body = req.body.toString();
        saver(body)
        // just write to file
        console.log("saved");
        res.send("done")
      } else {
        res.send(lustre);
      }
    } else {
      // https://stackoverflow.com/questions/10643981/how-to-get-the-unparsed-query-string-from-a-http-request-in-express
      var i = req.url.indexOf('?');
      var query = req.url.substr(i+1);
      // req.hostname removes port
      const result = handler(req.method, req.protocol,req.headers.host, req.path, query, req.body.toString());
      res.send(result);
    }
  });

  app.listen(port, () =>
    console.log(`HelloNode app listening on port ${port}!`)
  );
  app.listen(5001, () =>
    console.log(`HelloNode app listening on port ${5001}!`)
  );
  app.listen(5002, () =>
    console.log(`HelloNode app listening on port ${5002}!`)
  );
  app.listen(5003, () =>
    console.log(`HelloNode app listening on port ${5003}!`)
  );
  app.listen(5004, () =>
  console.log(`HelloNode app listening on port ${5004}!`)
);
}
