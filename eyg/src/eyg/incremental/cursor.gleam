import gleam/io
import gleam/list
import gleam/map
import gleam/result
import eygir/expression as e
import eyg/incremental/source.{Call, Fn, Let}

pub fn zip_match(node, path_element) {
  case node, path_element {
    Let(_, index, _), 0 -> index
    Let(_, _, index), 1 -> index
    Fn(_, index), 0 -> index
    Call(index, _), 0 -> index
    Call(_, index), 1 -> index
    _, _ -> {
      io.debug(#(node, path_element))
      todo("no_zip_match")
    }
  }
}

fn do_at(path, refs, current, zoom, root) {
  case path {
    [] -> #([current, ..zoom], root)
    [path_element, ..path] -> {
      let assert Ok(node) = list.at(refs, current)
      let zoom = [current, ..zoom]
      let current = zip_match(node, path_element)
      do_at(path, refs, current, zoom, root)
    }
  }
}

// root and refs together from tree
pub fn at(path, root, refs) {
  case path {
    [] -> #([], root)
    [path_element, ..path] -> {
      let assert Ok(node) = list.at(refs, root)
      let current = zip_match(node, path_element)
      do_at(path, refs, current, [], root)
    }
  }
}

fn do_at_map(path, refs, current, zoom, root) {
  case path {
    [] -> Ok(#([current, ..zoom], root))
    [path_element, ..path] -> {
      use node <- result.then(map.get(refs, root))
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

fn do_replace(old, new, zoom, rev) {
  case zoom {
    [] -> #(new, list.reverse(rev))
    [next, ..zoom] -> {
      let assert Ok(node) = list.at(list.reverse(rev), next)
      let exp = case node {
        Let(label, value, then) if value == old -> Let(label, new, then)
        Let(label, value, then) if then == old -> Let(label, value, new)
        Fn(param, body) if body == old -> Fn(param, new)
        Call(func, arg) if func == old -> Call(new, arg)
        Call(func, arg) if arg == old -> Call(func, new)
        _ -> todo("Can't have a path into literal")
      }
      let new = list.length(rev)
      let rev = [exp, ..rev]
      do_replace(next, new, zoom, rev)
    }
  }
}

pub fn replace(tree, cursor, refs) {
  let #(exp, acc) = source.do_from_tree(tree, list.reverse(refs))
  let new = list.length(acc)
  let rev = [exp, ..acc]
  case cursor {
    #([], old) -> do_replace(old, new, [], rev)
    #([old, ..zoom], root) ->
      do_replace(old, new, list.append(zoom, [root]), rev)
  }
}

// fn do_replace_map(old, new, zoom, rev) {
//   case zoom {
//     [] -> #(new, list.reverse(rev))
//     [next, ..zoom] -> {
//       let assert Ok(node) = list.at(list.reverse(rev), next)
//       let exp = case node {
//         Let(label, value, then) if value == old -> Let(label, new, then)
//         Let(label, value, then) if then == old -> Let(label, value, new)
//         Fn(param, body) if body == old -> Fn(param, new)
//         Call(func, arg) if func == old -> Call(new, arg)
//         Call(func, arg) if arg == old -> Call(func, new)
//         _ -> todo("Can't have a path into literal")
//       }
//       let new = list.length(rev)
//       let rev = [exp, ..rev]
//       do_replace_map(next, new, zoom, rev)
//     }
//   }
// }

// pub fn replace_map(tree, cursor, refs) {
//   let #(exp, acc) = source.do_from_tree(tree, list.reverse(refs))
//   let new = list.length(acc)
//   let rev = [exp, ..acc]
//   case cursor {
//     #([], old) -> do_replace_map(old, new, [], rev)
//     #([old, ..zoom], root) ->
//       do_replace_map(old, new, list.append(zoom, [root]), rev)
//   }
// }

pub fn inner(c) {
  case c {
    #([], root) -> root
    #([ref, ..], _) -> ref
  }
}
