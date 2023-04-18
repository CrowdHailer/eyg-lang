import gleam/io
import gleam/map
import gleam/result
import eyg/incremental/source

pub fn zip_match(node, path_element) {
  case node, path_element {
    source.Let(_, index, _), 0 -> index
    source.Let(_, _, index), 1 -> index
    source.Fn(_, index), 0 -> index
    source.Call(index, _), 0 -> index
    source.Call(_, index), 1 -> index
    _, _ -> {
      io.debug(#(node, path_element))
      panic("no_zip_match")
    }
  }
}

fn do_at_map(path, refs, current, zoom, root) {
  case path {
    [] -> Ok(#([current, ..zoom], root))
    [path_element, ..path] -> {
      use node <- result.then(map.get(refs, current))
      let zoom = [current, ..zoom]
      let current = zip_match(node, path_element)
      do_at_map(path, refs, current, zoom, root)
    }
  }
}

// root and refs together from tree
pub fn at_map(path, root, refs) {
  case path {
    [] -> Ok(#([], root))
    [path_element, ..path] -> {
      use node <- result.then(map.get(refs, root))
      let current = zip_match(node, path_element)
      do_at_map(path, refs, current, [], root)
    }
  }
}

pub fn inner(c) {
  case c {
    #([], root) -> root
    #([ref, ..], _) -> ref
  }
}
