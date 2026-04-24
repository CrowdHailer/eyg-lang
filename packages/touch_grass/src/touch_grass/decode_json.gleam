import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/dict
import gleam/list
import gleam/result
import julienne

pub const label = "DecodeJSON"

pub fn lift() {
  t.Binary
}

pub fn lower() {
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

pub const decode = cast.as_binary

pub fn encode(result) {
  case result {
    Ok(parsed) -> {
      let list =
        v.LinkedList(
          list.map(parsed, fn(item) {
            let #(term, depth) = item
            let term = case term {
              julienne.Boolean(True) -> v.true()
              julienne.Boolean(False) -> v.false()
              julienne.Null -> v.Tagged("Null", v.unit())
              julienne.String(value) -> v.Tagged("String", v.String(value))
              julienne.Integer(i) -> v.Tagged("Integer", v.Integer(i))
              julienne.Number(sign:, integer:, decimal:, exponent:) ->
                v.Tagged(
                  "Number",
                  v.Record(
                    dict.from_list([
                      #("sign", case sign {
                        julienne.Positive -> v.Tagged("Positive", v.unit())
                        julienne.Negative -> v.Tagged("Negative", v.unit())
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
              julienne.Array -> v.Tagged("Array", v.unit())
              julienne.Object -> v.Tagged("Object", v.unit())
              julienne.Field(f) -> v.Tagged("Field", v.String(f))
            }
            v.Record(
              dict.from_list([#("term", term), #("depth", v.Integer(depth))]),
            )
          }),
        )
      v.ok(list)
    }
    Error(reason) -> v.error(v.String(reason))
  }
}

pub fn sync(raw) {
  let result =
    julienne.parse_bits(raw)
    |> result.map_error(julienne.describe_reason)
  encode(result)
}
