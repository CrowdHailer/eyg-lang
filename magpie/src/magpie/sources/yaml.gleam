// erlang doesn't have good yaml libs but using it would get me a shell to try it in.
import gleam/dynamic.{Dynamic}
import gleam/list
import gleam/javascript
import gleam/javascript/array.{Array}
import magpie/store/in_memory.{B, I, L, S, Triple}

external fn load_yaml(String) -> Dynamic =
  "js-yaml" "load"

external fn do_entries(Dynamic) -> Array(#(String, Dynamic)) =
  "../../magpie_ffi.mjs" "entries"

pub fn entries(object) {
  array.to_list(do_entries(object))
}

pub fn read(raw) {
  try triples = parse(raw)
  Ok(in_memory.create_db(triples))
}

pub fn parse(raw) {
  load_yaml(raw)
  |> cast()
}

fn fresh(ref) {
  javascript.update_reference(ref, fn(x) { x + 1 })
}

fn cast(raw: Dynamic) -> Result(List(Triple), _) {
  let ref = javascript.make_reference(0)
  parse_field(entries(raw), fresh(ref), ref, [])
}

fn int(raw) {
  try value = dynamic.int(raw)
  Ok(#(I(value), []))
}

fn bool(raw) {
  try value = dynamic.bool(raw)
  Ok(#(B(value), []))
}

fn string(raw) {
  try value = dynamic.string(raw)
  Ok(#(S(value), []))
}

fn list(ref) {
  fn(raw) {
    try pairs =
      dynamic.list(dynamic.any([bool, int, string, list(ref), object(ref)]))(
        raw,
      )
    let #(value, sub) =
      pairs
      |> list.unzip
    Ok(#(L(value), list.flatten(sub)))
  }
}

fn object(ref) {
  fn(raw) {
    // object is tried last so safe to increment ref
    let self = fresh(ref)
    try triples = parse_field(entries(raw), self, ref, [])
    Ok(#(I(self), triples))
  }
}

fn parse_field(fields, parent, ref, acc) {
  case fields {
    [] -> Ok(list.reverse(acc))
    [#(key, value), ..rest] -> {
      try #(value, sub) =
        dynamic.any([bool, int, string, list(ref), object(ref)])(value)
      let triple = #(parent, key, value)
      parse_field(rest, parent, ref, [triple, ..list.append(sub, acc)])
    }
  }
}
