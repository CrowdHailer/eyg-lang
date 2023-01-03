import harness/ffi/env
import harness/ffi/integer
import harness/ffi/string
import eyg/runtime/interpreter as r
import eyg/analysis/typ as t

const true = r.Tagged("True", r.Record([]))

const false = r.Tagged("False", r.Record([]))

fn equal() {
  #(
    t.Fun(
      t.Unbound(1),
      t.Open(2),
      t.Fun(
        t.Unbound(1),
        t.Open(3),
        t.Union(t.Extend("True", t.unit, t.Extend("False", t.unit, t.Closed))),
      ),
    ),
    builtin2(fn(x, y, k) {
      case x == y {
        True -> true
        False -> false
      }
      |> r.continue(k, _)
    }),
  )
}

fn builtin2(f) {
  r.Builtin(fn(a, k) { r.continue(k, r.Builtin(fn(b, k) { f(a, b, k) })) })
}

external fn stringify(a) -> String =
  "" "JSON.stringify"

fn debug() {
  #(
    t.Fun(t.Unbound(1), t.Open(2), t.Binary),
    r.Builtin(fn(x, k) {
      r.Binary(stringify(x))
      |> r.continue(k, _)
    }),
  )
}

pub fn lib() {
  let #(types, values) =
    env.init()
    |> env.extend("equal", equal())
    |> env.extend("debug", debug())
    // integer
    |> env.extend("ffi_add", integer.add())
    |> env.extend("ffi_subtract", integer.subtract())
    |> env.extend("ffi_multiply", integer.multiply())
    |> env.extend("ffi_divide", integer.divide())
    |> env.extend("ffi_absolute", integer.absolute())
    |> env.extend("ffi_int_parse", integer.int_parse())
    |> env.extend("ffi_int_to_string", integer.int_to_string())
    // string
    |> env.extend("ffi_append", string.append())
    |> env.extend("ffi_uppercase", string.uppercase())
    |> env.extend("ffi_lowercase", string.lowercase())
    |> env.extend("ffi_length", string.length())
}
