import eyg/analysis/inference
import eyg/analysis/typ as t
import harness/stdlib
import platforms/cli

pub fn web() {
  t.Fun(
    t.Record(t.Extend(
      "method",
      t.Binary,
      t.Extend(
        "scheme",
        t.Binary,
        t.Extend(
          "host",
          t.Binary,
          t.Extend(
            "path",
            t.Binary,
            t.Extend("query", t.Binary, t.Extend("body", t.Binary, t.Closed)),
          ),
        ),
      ),
    )),
    t.Extend(
      "Log",
      #(t.Binary, t.Record(t.Closed)),
      t.Extend(
        "HTTP",
        #(
          t.Record(t.Extend(
            "method",
            t.Union(t.Extend("Get", t.unit, t.Closed)),
            t.Extend(
              "scheme",
              t.Union(t.Extend("HTTPS", t.unit, t.Closed)),
              t.Extend(
                "host",
                t.Binary,
                t.Extend(
                  "port",
                  t.option(t.Integer),
                  t.Extend(
                    "path",
                    t.Binary,
                    t.Extend(
                      "query",
                      t.option(t.Binary),
                      t.Extend(
                        "headers",
                        // TODO tuple of headers
                        t.LinkedList(t.Binary),
                        t.Extend("body", t.Binary, t.Closed),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )),
          t.Record(t.Closed),
        ),
        t.Closed,
      ),
    ),
    t.Record(t.Extend("body", t.Binary, t.Closed)),
  )
}

pub fn infer(prog) {
  inference.infer(
    stdlib.lib().0,
    prog,
    t.Record(t.Extend("cli", cli.typ(), t.Extend("web", web(), t.Closed))),
    t.Closed,
  )
}
