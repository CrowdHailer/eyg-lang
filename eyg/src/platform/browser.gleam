//  What does Roc call program + platform -> Application
// Does program space workspace things like tests live there
// browser.compile browser.harness
import gleam/option.{None, Some}
import gleam/string
// typer.common
import eyg/typer
import eyg/typer/monotype as t
import eyg/editor/type_info
import eyg/typer/polytype
import eyg/typer/harness

fn callback(arg, return, then) { 
      t.Function(arg, t.Function(t.Function(return, t.Unbound(then)), t.Unbound(then)))
}

pub fn harness() {
  harness.Harness(
    [
      #("equal", typer.equal_fn()), #("harness", string()), #("int", int()),
      #("spawn", polytype.Polytype(
        [5, -84],
        callback(t.Recursive(0, t.Function(t.Unbound(5), t.Unbound(0))), t.Native("Pid", [t.Unbound(5)]), -84)),
      ),
      #("send", polytype.Polytype(
        [15, -87],
        callback(t.Tuple([t.Native("Pid", [t.Unbound(15)]), t.Unbound(15)]), t.Tuple([]), -87))
      ),
      #("return", polytype.Polytype([-111], t.Function(t.Unbound(-111), t.Native("Run", [t.Unbound(-111)]))))
    ],

  )
}

fn int() {
  polytype.Polytype(
    [],
    t.Record(
      [
        #(
          "parse",
          t.Function(
            t.Binary,
            t.Union([#("OK", t.Native("Integer", [])), #("Error", t.Tuple([]))], None),
          ),
        ),
        #("to_string", t.Function(t.Native("Integer", []), t.Binary)),
        #(
          "add",
          t.Function(
            t.Tuple([t.Native("Integer", []), t.Native("Integer", [])]),
            t.Native("Integer", []),
          ),
        ),
        #(
          "multiply",
          t.Function(
            t.Tuple([t.Native("Integer", []), t.Native("Integer", [])]),
            t.Native("Integer", []),
          ),
        ),
        #("negate", t.Function(t.Native("Integer", []), t.Native("Integer", []))),
        #(
          "compare",
          t.Function(
            t.Tuple([t.Native("Integer", []), t.Native("Integer", [])]),
            t.Union(
              [#("Lt", t.Tuple([])), #("Eq", t.Tuple([])), #("Gt", t.Tuple([]))],
              None,
            ),
          ),
        ),
        #("zero", t.Native("Integer", [])),
        #("one", t.Native("Integer", [])),
        #("two", t.Native("Integer", [])),
      ],
      None,
    ),
  )
}

// fn p0() {
// }
// Polytimes are always instantiated we can reduce to lowest number when put in scope
// perhaps they should be letters or similar
pub fn string() {
  polytype.Polytype(
    [1, 2, 3, 4, 5, 6, 7,8, 9, 10, 11],
    t.Record(
      [
        #(
          "split",
          t.Function(
            t.Tuple([t.Binary, t.Binary]),
            t.Function(
              t.Tuple([
                t.Function(t.Tuple([]), t.Unbound(1)),
                t.Function(
                  // TODO need recursive type definition
                  t.Tuple([t.Binary, t.Unbound(999)]),
                  t.Unbound(1),
                ),
              ]),
              t.Unbound(1),
            ),
          ),
        ),
        #("concat", t.Function(t.Tuple([t.Binary, t.Binary]), t.Binary)),
        #("debug", t.Function(t.Unbound(2), t.Unbound(2))),
        // #("inspect", t.Function(t.Unbound(6), t.Binary)),
        #(
          "compile",
          t.Function(
            t.Tuple([t.Binary, t.Binary]),
            t.Union([#("OK", t.Unbound(4)), #("Error", t.Binary)], Some(5)),
          ),
        ),
        #("source", t.Function(t.Tuple([]), t.Binary)),
        #("fetch", t.Function(t.Binary, t.Function(t.Function(t.Binary, t.Unbound(7)), t.Tuple([])))),
        // TODO this should probably be returning JSON not unbound
        #("key", t.Function(t.Tuple([t.Unbound(8), t.Binary]), t.Unbound(9))),
        #("deserialize", t.Function(t.Binary, t.Native("JSON", []))),
        #("spawn", t.Function(t.Recursive(0, t.Function(t.Unbound(10), t.Unbound(0))), t.Function(t.Function(t.Native("Address", [t.Unbound(10)]), t.Unbound(11)), t.Unbound(11)))),
      ],
      None,
    ),
  )
}
