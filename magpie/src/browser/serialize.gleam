import gleam/dynamic
import gleam/json
import gleam_community/codec
import magpie/query
import magpie/store/in_memory

pub type Query {
  Query(find: List(String), patterns: List(query.Pattern))
}

fn tuple3(a, b, c) {
  codec.from(
    fn(t) {
      let #(v1, v2, v3) = t
      json.array(
        [codec.encoder(a)(v1), codec.encoder(b)(v2), codec.encoder(c)(v3)],
        fn(x) { x },
      )
    },
    dynamic.tuple3(codec.decoder(a), codec.decoder(a), codec.decoder(a)),
  )
}

fn bool() {
  codec.from(json.bool, dynamic.bool)
}

pub fn pattern() {
  tuple3(match(), match(), match())
}

pub fn value() {
  codec.custom3(fn(b, i, s, value) {
    case value {
      in_memory.B(value) -> b(value)
      in_memory.I(value) -> i(value)
      in_memory.S(value) -> s(value)
      _ -> todo("no lists in dataset and no custom4 in codec")
    }
  })
  |> codec.variant1("B", in_memory.B, bool())
  |> codec.variant1("I", in_memory.I, codec.int())
  |> codec.variant1("S", in_memory.S, codec.string())
  |> codec.construct()
}

pub fn match() {
  codec.custom2(fn(variable, constant, value) {
    case value {
      query.Variable(var) -> variable(var)
      query.Constant(value) -> constant(value)
    }
  })
  |> codec.variant1("V", query.Variable, codec.string())
  |> codec.variant1("C", query.Constant, value())
  |> codec.construct()
}

pub fn query() {
  codec.custom1(fn(q, value) {
    let Query(f, p) = value
    q(f, p)
  })
  |> codec.variant2(
    "",
    Query,
    codec.list(codec.string()),
    codec.list(pattern()),
  )
  |> codec.construct()
}

pub fn relations() {
  codec.list(codec.list(value()))
}
