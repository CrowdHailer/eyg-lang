import gleam/map
import gleam/result
import eyg/incremental/source as e

pub type Cursor =
  #(List(Int), Int)

fn zip_match(node, path_element) {
  case node, path_element {
    e.Let(_, index, _), 0 -> Ok(index)
    e.Let(_, _, index), 1 -> Ok(index)
    e.Fn(_, index), 0 -> Ok(index)
    e.Call(index, _), 0 -> Ok(index)
    e.Call(_, index), 1 -> Ok(index)
    _, _ -> Error(Nil)
  }
}

fn do_at(path, refs, current, zoom, root) {
  case path {
    [] -> Ok(#([current, ..zoom], root))
    [path_element, ..path] -> {
      use node <- result.then(map.get(refs, current))
      let zoom = [current, ..zoom]
      use current <- result.then(zip_match(node, path_element))
      do_at(path, refs, current, zoom, root)
    }
  }
}

pub fn at(path, root, refs) {
  case path {
    [] -> Ok(#([], root))
    [path_element, ..path] -> {
      use node <- result.then(map.get(refs, root))
      use current <- result.then(zip_match(node, path_element))
      do_at(path, refs, current, [], root)
    }
  }
}

pub fn inner(c) {
  case c {
    #([], root) -> root
    #([ref, ..], _) -> ref
  }
}

pub fn expression(c, source) {
  map.get(source, inner(c))
}
