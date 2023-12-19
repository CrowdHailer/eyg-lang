import gleam/dynamic
import gleam/json
import gleam_community/codec
import magpie/query
import magpie/store/in_memory

pub type Query {
  Query(find: List(String), patterns: List(query.Pattern))
}

fn tuple3(a: codec.Codec(a), b: codec.Codec(b), c: codec.Codec(c)) {
  codec.from(
    fn(t) {
      let #(v1, v2, v3) = t
      json.array(
        [codec.encoder(a)(v1), codec.encoder(b)(v2), codec.encoder(c)(v3)],
        fn(x) { x },
      )
    },
    dynamic.tuple3(codec.decoder(a), codec.decoder(b), codec.decoder(c)),
  )
}

fn tuple2(a: codec.Codec(a), b: codec.Codec(b)) {
  codec.from(
    fn(t) {
      let #(v1, v2) = t
      json.array([codec.encoder(a)(v1), codec.encoder(b)(v2)], fn(x) { x })
    },
    dynamic.tuple2(codec.decoder(a), codec.decoder(b)),
  )
}

fn bool() {
  codec.from(json.bool, dynamic.bool)
}

pub fn pattern() {
  tuple3(match(), match(), match())
}

pub fn value() {
  todo
  // codec.custom3(fn(b, i, s, value) {
  //   case value {
  //     in_memory.B(value) -> b(value)
  //     in_memory.I(value) -> i(value)
  //     in_memory.S(value) -> s(value)
  //     _ -> panic("no lists in dataset and no custom4 in codec")
  //   }
  // })
  // |> codec.variant1("B", in_memory.B, bool())
  // |> codec.variant1("I", in_memory.I, codec.int())
  // |> codec.variant1("S", in_memory.S, codec.string())
  // |> codec.construct()
}

pub fn match() {
  todo
  // codec.custom2(fn(variable, constant, value) {
  //   case value {
  //     query.Variable(var) -> variable(var)
  //     query.Constant(value) -> constant(value)
  //   }
  // })
  // |> codec.variant1("V", query.Variable, codec.string())
  // |> codec.variant1("C", query.Constant, value())
  // |> codec.construct()
}

pub fn query() {
  todo
  // codec.custom1(fn(q, value) {
  //   let Query(f, p) = value
  //   q(f, p)
  // })
  // |> codec.variant2("", Query, codec.list(codec.string()), codec.list(pattern()),
  // )
  // |> codec.construct()
}

pub fn relations() {
  codec.list(codec.list(value()))
}

pub type DBView {
  DBView(triple_count: Int, attribute_suggestions: List(#(String, Int)))
}

// need variant3 if we want to use codec more
// value_suggestions: List(#(String, Int, Nil)),

pub fn db_view() -> codec.Codec(DBView) {
  todo
  // codec.custom1(fn(q, value) {
  //   let DBView(triple_count, attribute_suggestions) = value
  //   q(triple_count, attribute_suggestions)
  // })
  // |> codec.variant2(
  //   "",
  //   DBView,
  //   codec.int(),
  //   codec.list(tuple2(codec.string(), codec.int())),
  // )
  // // codec.list(tuple3(codec.string(), codec.int(), codec.succeed(Nil))),
  // |> codec.construct()
}
