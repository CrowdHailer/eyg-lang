import dag_json as codec
import eyg/ir/tree as ir
import gleam/dynamic
import gleam/dynamic/decode as d
import gleam/json
import multiformats/cid/v1
import multiformats/hashes

fn label_decoder(
  for: fn(String) -> ir.Expression(meta),
  meta: meta,
) -> d.Decoder(ir.Node(meta)) {
  use label <- d.field("l", d.string)
  d.success(#(for(label), meta))
}

pub const vacant_cid = v1.Cid(
  297,
  hashes.Multihash(
    hashes.Sha256,
    <<
      143,
      171,
      132,
      193,
      178,
      239,
      11,
      237,
      187,
      22,
      81,
      164,
      153,
      54,
      34,
      109,
      16,
      139,
      216,
      209,
      66,
      180,
      135,
      86,
      79,
      251,
      7,
      31,
      89,
      235,
      100,
      152,
    >>,
  ),
)

/// create a decoder that will parse JSON source to an annotated tree with the given metadata.
pub fn decoder(meta: meta) -> d.Decoder(ir.Node(meta)) {
  use switch <- d.field("0", d.string)
  case switch {
    "v" -> label_decoder(ir.Variable, meta)
    "f" -> {
      use label <- d.field("l", d.string)
      use body <- d.field("b", decoder(meta))
      d.success(#(ir.Lambda(label, body), meta))
    }
    "a" -> {
      use function <- d.field("f", decoder(meta))
      use argument <- d.field("a", decoder(meta))
      d.success(#(ir.Apply(function, argument), meta))
    }
    "l" -> {
      use label <- d.field("l", d.string)
      use value <- d.field("v", decoder(meta))
      use then <- d.field("t", decoder(meta))
      d.success(#(ir.Let(label, value, then), meta))
    }
    "x" -> {
      use bytes <- d.field("v", codec.decode_bytes())
      d.success(#(ir.Binary(bytes), meta))
    }
    "i" -> {
      use value <- d.field("v", d.int)
      d.success(#(ir.Integer(value), meta))
    }
    "s" -> {
      use value <- d.field("v", d.string)
      d.success(#(ir.String(value), meta))
    }
    "ta" -> d.success(#(ir.Tail, meta))
    "c" -> d.success(#(ir.Cons, meta))
    "z" -> d.success(#(ir.Vacant, meta))
    "u" -> d.success(#(ir.Empty, meta))
    "e" -> label_decoder(ir.Extend, meta)
    "g" -> label_decoder(ir.Select, meta)
    "o" -> label_decoder(ir.Overwrite, meta)
    "t" -> label_decoder(ir.Tag, meta)
    "m" -> label_decoder(ir.Case, meta)
    "n" -> d.success(#(ir.NoCases, meta))
    "p" -> label_decoder(ir.Perform, meta)
    "h" -> label_decoder(ir.Handle, meta)
    "b" -> label_decoder(ir.Builtin, meta)
    "#" -> {
      use cid <- d.field("l", codec.decode_cid())
      d.success(#(ir.ContentReference(cid), meta))
    }
    "@" -> {
      use package <- d.field("p", d.string)
      // version field used to be called release, so still uses r field in serialized code
      use version <- d.field("r", d.int)
      use cid <- d.field("l", codec.decode_cid())
      d.success(#(ir.ReleaseReference(package, version, cid), meta))
    }
    "." -> {
      use location <- d.field("i", d.string)
      d.success(#(ir.RelativeReference(location), meta))
    }
    _ -> {
      d.failure(#(ir.Vacant, meta), "valid node key")
    }
  }
}

@deprecated("This function is tied to Nil metadata, use the `decoder` directly instead")
pub fn decode(
  json: dynamic.Dynamic,
) -> Result(ir.Node(Nil), List(d.DecodeError)) {
  d.run(json, decoder(Nil))
}

@deprecated("This function is tied to Nil metadata, use the `decoder` directly instead")
pub fn from_block(data: BitArray) -> Result(ir.Node(Nil), json.DecodeError) {
  json.parse_bits(data, decoder(Nil))
}

fn node(name: String, attributes: List(#(String, json.Json))) -> json.Json {
  codec.object([#("0", codec.string(name)), ..attributes])
}

fn label(value: String) -> #(String, json.Json) {
  #("l", codec.string(value))
}

pub fn to_data_model(tree: ir.Node(meta)) -> json.Json {
  let #(exp, _meta) = tree
  case exp {
    ir.Variable(x) -> node("v", [label(x)])
    // function
    ir.Lambda(x, body) -> node("f", [label(x), #("b", to_data_model(body))])
    ir.Apply(func, arg) ->
      node("a", [#("f", to_data_model(func)), #("a", to_data_model(arg))])
    ir.Let(x, value, then) ->
      [label(x), #("v", to_data_model(value)), #("t", to_data_model(then))]
      |> node("l", _)
    // b already taken when adding binary
    ir.Binary(b) -> node("x", [#("v", codec.binary(b))])
    ir.Integer(i) -> node("i", [#("v", codec.int(i))])
    // string
    ir.String(s) -> node("s", [#("v", codec.string(s))])
    ir.Tail -> node("ta", [])
    ir.Cons -> node("c", [])
    // zero
    ir.Vacant -> node("z", [])
    // unit
    ir.Empty -> node("u", [])
    ir.Extend(x) -> node("e", [label(x)])
    // get
    ir.Select(x) -> node("g", [label(x)])
    ir.Overwrite(x) -> node("o", [label(x)])
    ir.Tag(x) -> node("t", [label(x)])
    // match
    ir.Case(x) -> node("m", [label(x)])
    ir.NoCases -> node("n", [])
    ir.Perform(x) -> node("p", [label(x)])
    ir.Handle(x) -> node("h", [label(x)])
    ir.Builtin(x) -> node("b", [label(x)])
    ir.ContentReference(identifier) ->
      node("#", [#("l", codec.cid(identifier))])
    ir.ReleaseReference(p, r, i) ->
      node("@", [
        #("p", codec.string(p)),
        #("r", codec.int(r)),
        #("l", codec.cid(i)),
      ])
    ir.RelativeReference(identifier) ->
      node(".", [#("i", codec.string(identifier))])
  }
}

pub fn to_block(data: ir.Node(meta)) -> BitArray {
  codec.encode(to_data_model(data))
}

pub fn to_string(data: ir.Node(meta)) -> String {
  json.to_string(to_data_model(data))
}
