import dag_json as codec
import eyg/ir/tree as ir
import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleam/result
import multiformats/cid

fn label_decoder(for, meta) {
  use label <- decode.field("l", decode.string)
  decode.success(#(for(label), meta))
}

const vacant_cid = "baguqeerar6vyjqns54f63oywkgsjsnrcnuiixwgrik2iovsp7mdr6wplmsma"

fn cid_decoder() {
  decode.new_primitive_decoder("CID", fn(raw) {
    case cid.decode(raw) {
      Ok(cid) -> Ok(cid.to_string(cid))
      Error(Nil) -> Error(vacant_cid)
    }
  })
}

pub fn decoder(meta) {
  use switch <- decode.field("0", decode.string)
  case switch {
    "v" -> label_decoder(ir.Variable, meta)
    "f" -> {
      use label <- decode.field("l", decode.string)
      use body <- decode.field("b", decoder(meta))
      decode.success(#(ir.Lambda(label, body), meta))
    }
    "a" -> {
      use function <- decode.field("f", decoder(meta))
      use argument <- decode.field("a", decoder(meta))
      decode.success(#(ir.Apply(function, argument), meta))
    }
    "l" -> {
      use label <- decode.field("l", decode.string)
      use value <- decode.field("v", decoder(meta))
      use then <- decode.field("t", decoder(meta))
      decode.success(#(ir.Let(label, value, then), meta))
    }
    "x" -> {
      use bytes <- decode.field("v", decode.bit_array)
      decode.success(#(ir.Binary(bytes), meta))
    }
    "i" -> {
      use value <- decode.field("v", decode.int)
      decode.success(#(ir.Integer(value), meta))
    }
    "s" -> {
      use value <- decode.field("v", decode.string)
      decode.success(#(ir.String(value), meta))
    }
    "ta" -> decode.success(#(ir.Tail, meta))
    "c" -> decode.success(#(ir.Cons, meta))
    "z" -> decode.success(#(ir.Vacant, meta))
    "u" -> decode.success(#(ir.Empty, meta))
    "e" -> label_decoder(ir.Extend, meta)
    "g" -> label_decoder(ir.Select, meta)
    "o" -> label_decoder(ir.Overwrite, meta)
    "t" -> label_decoder(ir.Tag, meta)
    "m" -> label_decoder(ir.Case, meta)
    "n" -> decode.success(#(ir.NoCases, meta))
    "p" -> label_decoder(ir.Perform, meta)
    "h" -> label_decoder(ir.Handle, meta)
    "b" -> label_decoder(ir.Builtin, meta)
    "#" -> {
      use cid <- decode.field("l", cid_decoder())
      decode.success(#(ir.Reference(cid), meta))
    }
    "@" -> {
      use package <- decode.field("p", decode.string)
      use release <- decode.field("r", decode.int)
      use cid <- decode.field("l", cid_decoder())
      decode.success(#(ir.Release(package, release, cid), meta))
    }
    _ -> {
      decode.failure(#(ir.Vacant, meta), "valid node key")
    }
  }
}

pub fn decode(json) {
  decode.run(json, decoder(Nil))
}

pub fn from_block(data) {
  case codec.decode(data) {
    Ok(json) -> decode(json)
    Error(reason) -> Error([decode.DecodeError("valid dag-json", reason, [])])
  }
}

pub fn decode_dynamic_error(json) {
  decode(json)
  |> result.map_error(fn(errors) {
    list.map(errors, fn(error) {
      let decode.DecodeError(expected, found, path) = error
      dynamic.DecodeError(expected, found, path)
    })
  })
}

fn node(name, attributes) {
  codec.object([#("0", codec.string(name)), ..attributes])
}

fn label(value) {
  #("l", codec.string(value))
}

pub fn to_data_model(tree) {
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
    ir.Reference(identifier) -> node("#", [#("l", codec.cid(identifier))])
    ir.Release(p, r, i) ->
      node("@", [
        #("p", codec.string(p)),
        #("r", codec.int(r)),
        #("l", codec.cid(i)),
      ])
  }
}

pub fn to_block(data) {
  codec.encode(to_data_model(data))
}
