import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import flat_json
import gleam/dict
import gleam/javascript/promise
import gleam/list

pub const l = "DecodeJSON"

pub const lift = t.String

pub fn reply() {
  t.result(
    t.List(
      t.record([
        #(
          "term",
          t.union([
            #("True", t.unit),
            #("False", t.unit),
            #("Null", t.unit),
            #("Integer", t.Integer),
            #("String", t.String),
            #("Array", t.unit),
            #("Object", t.unit),
            #("Field", t.String),
          ]),
        ),
        #("depth", t.Integer),
      ]),
    ),
    t.String,
  )
}

pub fn type_() {
  #(l, #(lift, reply()))
}

pub fn cast(lift) {
  cast.as_binary(lift)
}

pub fn run(encoded) {
  promise.resolve(sync(encoded))
}

pub fn sync(encoded) {
  result_to_eyg(do(encoded))
}

// fn impl(lift) {
//   use message <- result.try(cast(lift))
//   let Nil = do(message)
//   Ok(v.unit())
// }

// pub fn blocking(lift) {
//   use value <- result.map(impl(lift))
//   promise.resolve(value)
// }

// pub fn preflight(lift) {
//   use message <- result.try(cast(lift))
//   Ok(fn() {
//     let Nil = do(message)
//     promise.resolve(v.unit())
//   })
// }

pub fn do(encoded) {
  flat_json.parse_bits(encoded)
}

fn result_to_eyg(parsed) {
  case parsed {
    Ok(parsed) -> {
      let list =
        v.LinkedList(
          list.map(parsed, fn(item) {
            let #(term, depth) = item
            let term = case term {
              flat_json.Boolean(True) -> v.true()
              flat_json.Boolean(False) -> v.false()
              flat_json.Null -> v.Tagged("Null", v.unit())
              flat_json.String(value) -> v.Tagged("String", v.String(value))
              flat_json.Integer(i) -> v.Tagged("Integer", v.Integer(i))
              flat_json.Number(sign:, integer:, decimal:, exponent:) ->
                v.Tagged(
                  "Number",
                  v.Record(
                    dict.from_list([
                      #("sign", case sign {
                        flat_json.Positive -> v.Tagged("Positive", v.unit())
                        flat_json.Negative -> v.Tagged("Negative", v.unit())
                      }),
                      #("integer", v.Integer(integer)),
                      #(
                        "decimal",
                        v.Record(
                          dict.from_list([
                            #("numerator", v.Integer(decimal.0)),
                            #("size", v.Integer(decimal.1)),
                          ]),
                        ),
                      ),
                      #("exponent", v.Integer(exponent)),
                    ]),
                  ),
                )
              flat_json.Array -> v.Tagged("Array", v.unit())
              flat_json.Object -> v.Tagged("Object", v.unit())
              flat_json.Field(f) -> v.Tagged("String", v.String(f))
            }
            v.Record(
              dict.from_list([#("term", term), #("depth", v.Integer(depth))]),
            )
          }),
        )
      v.ok(list)
    }
    Error(_) -> v.error(v.String("failed to parse json"))
  }
}
