// erlang doesn't have good yaml libs but using it would get me a shell to try it in.
import gleam/dynamic.{type Dynamic}
import gleam/javascript
import gleam/javascript/array.{type Array}
import gleam/list
import gleam/result
import magpie/store/in_memory.{type Triple, B, I, L, S}
import plinth/node/fs

@external(javascript, "js-yaml", "load")
fn load_yaml(file: String) -> Dynamic

@external(javascript, "../../magpie_ffi.mjs", "entries")
fn do_entries(rows: Dynamic) -> Array(#(String, Dynamic))

pub fn entries(object) {
  array.to_list(do_entries(object))
}

pub fn read_files(files) {
  let ref = javascript.make_reference(0)
  let assert Ok(read) =
    list.try_map(files, fn(f) {
      use source <- result.then(
        fs.read_file_sync(f)
        |> result.replace_error("failed to read file"),
      )
      parse(source, ref)
      |> result.replace_error("failed to parse source")
    })
  list.flatten(read)
  |> in_memory.create_db
}

pub fn read_string(raw) {
  let ref = javascript.make_reference(0)
  use triples <- result.then(parse(raw, ref))
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
  use value <- result.then(dynamic.int(raw))
  Ok(#(I(value), []))
}

fn bool(raw) {
  use value <- result.then(dynamic.bool(raw))
  Ok(#(B(value), []))
}

fn string(raw) {
  use value <- result.then(dynamic.string(raw))
  Ok(#(S(value), []))
}

fn list(ref) {
  fn(raw) {
    use pairs <- result.then(
      dynamic.list(dynamic.any([bool, int, string, list(ref), object(ref)]))(
        raw,
      ),
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
    use triples <- result.then(parse_field(entries(raw), self, ref, []))
    Ok(#(I(self), triples))
  }
}

fn parse_field(fields, parent, ref, acc) {
  case fields {
    [] -> Ok(list.reverse(acc))
    [#(key, value), ..rest] -> {
      use #(value, sub) <- result.then(
        dynamic.any([bool, int, string, list(ref), object(ref)])(value),
      )
      let triple = #(parent, key, value)
      parse_field(rest, parent, ref, [triple, ..list.append(sub, acc)])
    }
  }
}
