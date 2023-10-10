import eyg/analysis/inference
import eyg/analysis/typ as t
import harness/stdlib

pub fn web() {
  t.Fun(
    t.Record(t.Extend(
      "method",
      t.Str,
      t.Extend(
        "scheme",
        t.Str,
        t.Extend(
          "host",
          t.Str,
          t.Extend(
            "path",
            t.Str,
            t.Extend("query", t.Str, t.Extend("body", t.Str, t.Closed)),
          ),
        ),
      ),
    )),
    t.Extend(
      "Log",
      #(t.Str, t.Record(t.Closed)),
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
                t.Str,
                t.Extend(
                  "port",
                  t.option(t.Integer),
                  t.Extend(
                    "path",
                    t.Str,
                    t.Extend(
                      "query",
                      t.option(t.Str),
                      t.Extend(
                        "headers",
                        // I don't have tuples for a list of headers so this is not yet implemented
                        t.LinkedList(t.Str),
                        t.Extend("body", t.Str, t.Closed),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )),
          t.Record(t.Closed),
        ),
        t.Extend(
          "Await",
          #(t.Unbound(-1), t.Unbound(-1)),
          // It might be better to have constants for all these effects
          t.Extend("Wait", #(t.Integer, t.Unbound(-2)), t.Closed),
        ),
      ),
    ),
    t.Record(t.Extend("body", t.Str, t.Closed)),
  )
}

pub fn infer(prog) {
  inference.infer(
    stdlib.lib().0,
    prog,
    t.Record(t.Extend("web", web(), t.Closed)),
    t.Closed,
  )
}
