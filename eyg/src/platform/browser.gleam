//  What does Roc call program + platform -> Application
// Does program space workspace things like tests live there
// browser.compile browser.harness
import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
// typer.common
import eyg/typer
import eyg/typer/monotype as t
import eyg/editor/type_info
import eyg/typer/polytype
import eyg/typer/harness

// TODO make all effectual functions open

// Adding variables never have unbound types, but they can be generic
pub fn harness() {
  harness.Harness([#("equal", typer.equal_fn()), #("builtin", builtins())])
  // #("int", int()),
}

// Exffects are free variables
fn builtins() {
  polytype.Polytype([], t.Record([], None))
  |> add_field(
    "append",
    t.Function(t.Tuple([t.Binary, t.Binary]), t.Binary, t.empty),
  )
  |> add_field("uppercase", t.Function(t.Binary, t.Binary, t.empty))
  |> add_field("lowercase", t.Function(t.Binary, t.Binary, t.empty))
  |> add_field(
    "replace",
    t.Function(t.Tuple([t.Binary, t.Binary, t.Binary]), t.Binary, t.empty),
  )
}

fn add_field(state, key, type_) {
  let polytype.Polytype(generic, t.Record(fields, None)) = state
  let min = list.fold(generic, 0, int.max) + 1

  let polytype.Polytype(new, type_) =
    type_
    // really only a polytype should be shrank?
    |> polytype.shrink_to(min)
    |> polytype.generalise([])

  let generic = list.append(generic, new)
  let fields = list.append(fields, [#(key, type_)])
  polytype.Polytype(generic, t.Record(fields, None))
}

// TODO we can remove these
fn int() {
  polytype.Polytype(
    [],
    t.Record(
      [
        #(
          "parse",
          t.Function(
            t.Binary,
            t.Union(
              [#("OK", t.Native("Integer", [])), #("Error", t.Tuple([]))],
              None,
            ),
            t.empty,
          ),
        ),
        #("to_string", t.Function(t.Native("Integer", []), t.Binary, t.empty)),
        #(
          "add",
          t.Function(
            t.Tuple([t.Native("Integer", []), t.Native("Integer", [])]),
            t.Native("Integer", []),
            t.empty,
          ),
        ),
        #(
          "multiply",
          t.Function(
            t.Tuple([t.Native("Integer", []), t.Native("Integer", [])]),
            t.Native("Integer", []),
            t.empty,
          ),
        ),
        #(
          "negate",
          t.Function(t.Native("Integer", []), t.Native("Integer", []), t.empty),
        ),
        #(
          "compare",
          t.Function(
            t.Tuple([t.Native("Integer", []), t.Native("Integer", [])]),
            t.Union(
              [#("Lt", t.Tuple([])), #("Eq", t.Tuple([])), #("Gt", t.Tuple([]))],
              None,
            ),
            t.empty,
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
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
    t.Record(
      [
        #(
          "split",
          t.Function(
            t.Tuple([t.Binary, t.Binary]),
            t.Function(
              t.Tuple([
                t.Function(t.Tuple([]), t.Unbound(1), t.empty),
                t.Function(
                  // TODO need recursive type definition
                  t.Tuple([t.Binary, t.Unbound(999)]),
                  t.Unbound(1),
                  t.empty,
                ),
              ]),
              t.Unbound(1),
              t.empty,
            ),
            t.empty,
          ),
        ),
        #(
          "concat",
          t.Function(t.Tuple([t.Binary, t.Binary]), t.Binary, t.empty),
        ),
        #(
          "debug",
          t.Function(
            t.Unbound(2),
            t.Unbound(2),
            t.Union([#("Log", t.Binary)], Some(12)),
          ),
        ),
        // #("inspect", t.Function(t.Unbound(6), t.Binary)),
        #(
          "compile",
          t.Function(
            t.Tuple([t.Binary, t.Binary]),
            t.Union([#("OK", t.Unbound(4)), #("Error", t.Binary)], Some(5)),
            t.empty,
          ),
        ),
        #("source", t.Function(t.Tuple([]), t.Binary, t.empty)),
        #(
          "fetch",
          t.Function(
            t.Binary,
            t.Function(
              t.Function(t.Binary, t.Unbound(7), t.empty),
              t.Tuple([]),
              t.empty,
            ),
            t.empty,
          ),
        ),
        // TODO this should probably be returning JSON not unbound
        #(
          "key",
          t.Function(t.Tuple([t.Unbound(8), t.Binary]), t.Unbound(9), t.empty),
        ),
        #("deserialize", t.Function(t.Binary, t.Native("JSON", []), t.empty)),
      ],
      // TODO fix in case of spawn test
      // #("spawn", t.Function(t.Recursive(0, t.Function(t.Unbound(10), t.Unbound(0))), t.Function(t.Function(t.Native("Address", [t.Unbound(10)]), t.Unbound(11)), t.Unbound(11)))),
      None,
    ),
  )
}
