import gleam/io
import gleam/list
import gleam/map
import gleam/option.{None}
import gleam/result
import gleam/string
import gleam/javascript
import gleam/javascript/array.{Array}
import eyg/analysis/inference
import eyg/analysis/unification
import eyg/analysis/scheme
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import eygir/expression as e
import eygir/decode
import harness/stdlib

pub fn infer(prog) {
  inference.infer(
    stdlib.lib().0,
    prog,
    t.Record(t.Extend(
      "cli",
      t.Fun(t.Record(t.Closed), t.Open(-1000), t.Unbound(-1001)),
      t.Extend(
        "web",
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
                  t.Extend(
                    "query",
                    t.Binary,
                    t.Extend("body", t.Binary, t.Closed),
                  ),
                ),
              ),
            ),
          )),
          t.Open(-1002),
          t.Record(t.Extend("body", t.Binary, t.Closed)),
        ),
        t.Open(-1003),
      ),
    )),
    t.Open(-1004),
  )
}
