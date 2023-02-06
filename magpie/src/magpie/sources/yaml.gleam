// erlang doesn't have good yaml libs but using it would get me a shell to try it in.
import gleam/dynamic.{Dynamic}
import gleam/io
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

external fn read_file_sync(String, String) -> String =
  "fs" "readFileSync"

pub fn read_files(files) {
  let ref = javascript.make_reference(0)
  assert Ok(read) =
    list.try_map(
      files,
      fn(f) {
        let source = read_file_sync(f, "utf8")
        parse(source, ref)
      },
    )
  list.flatten(read)
  |> in_memory.create_db
}

pub fn read_string(raw) {
  let ref = javascript.make_reference(0)
  try triples = parse(raw, ref)
  Ok(in_memory.create_db(triples))
}

// maybe all public api's should be on lists,relations everywhere.
pub fn parse_one(raw) {
  let ref = javascript.make_reference(0)

  parse(raw, ref)
}

fn parse(raw, ref) {
  load_yaml(raw)
  |> cast(ref)
}

fn fresh(ref) {
  javascript.update_reference(ref, fn(x) { x + 1 })
}

fn cast(raw: Dynamic, ref) -> Result(List(Triple), _) {
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
