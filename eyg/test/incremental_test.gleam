import gleam/io
import gleam/list
import gleam/map.{Map}
import gleam/option
import gleam/set.{Set}
import gleam/setx
import eygir/expression as e

pub type Exp {
  Var(String)
  Fn(String, Int)
  Let(String, Int, Int)
  Call(Int, Int)
  Integer(Int)
  String(String)
}

type Source =
  Map(Int, #(Exp, Set(String)))

fn let_(label, value, then) {
  fn(count) {
    let #(count, v) = value(count)
    let value_id = count - 1
    let assert Ok(#(_, free_v)) = map.get(v, value_id)

    let #(count, t) = then(count)
    let then_id = count - 1
    let assert Ok(#(_, free_t)) = map.get(t, then_id)
    let free = set.union(free_v, set.delete(free_t, label))

    #(
      count,
      map.merge(v, t)
      |> map.insert(count, #(Let(label, value_id, then_id), free)),
    )
  }
}

fn var(x) {
  fn(count) {
    #(
      count + 1,
      map.new()
      |> map.insert(
        count,
        #(
          Var(x),
          set.new()
          |> set.insert(x),
        ),
      ),
    )
  }
}

fn integer(i) {
  fn(count) {
    #(
      count + 1,
      map.new()
      |> map.insert(count, #(Integer(i), set.new())),
    )
  }
}

// TODO ask
// type State {
//   State(next: Int)
// }

// fn fresh(then) { 

//  }

// pub fn function_name() -> Nil {
//   use i <- fresh()
// }

pub type T {
  TInt
}

fn w(env, exp, source, fresh, cache) {
  let assert Ok(#(node, free)) = map.get(source, exp)
  io.debug(node)
  let #(s, t, fresh, cache) = case node {
    Let(label, v, t) -> {
      let #(s1, t1, fresh, cache) = w(env, v, source, fresh, cache)
      let env1 = map.insert(env, label, t1)
      let #(s2, t2, fresh, cache) = w(env1, t, source, fresh, cache)
      // TODO real s
      #(s2, t2, fresh, cache)
    }
    Var(x) -> {
      let assert Ok(t) = map.get(env, x)
      #(Nil, t, fresh, cache)
    }
    Integer(_) -> #(Nil, TInt, fresh, cache)

    _ -> todo("22w")
  }
  let cache =
    map.update(
      cache,
      exp,
      fn(previous) {
        let by_env = option.unwrap(previous, map.new())
        map.insert(by_env, map.take(env, set.to_list(free)), t)
      },
    )
  #(s, t, fresh, cache)
}

fn unzip(cursor, exp, source) {
  let id = map.size(source)
  let source = map.insert(source, id, exp)
  let #(rev, _initial) = cursor
  case rev {
    [] -> #(id, source)
  }

  // [key, parent, ..rest] | [key] parent
  // [x, ..rest] -> {
  //   let assert Ok(#(node, free)) = map.get(source, x)
  // }
  todo("banana")
}

// pub fn function_name_test() -> Nil {
//   let #(size, source) = let_("x", integer(2), var("x"))(0)
//   io.debug(size)
//   source
//   |> map.to_list
//   |> io.debug

//   io.debug("---")
//   let path = [0]
//   let cursor = zip(source, path, 2)
//   io.debug(cursor)

//   io.debug("---!!!!!")
//   unzip(cursor, #(String("foo"), set.new()), source)

//   let #(s, t, fresh, cache) = w(map.new(), 2, source, 0, map.new())
//   map.get(cache, 0)
//   |> io.debug

//   todo
// }

fn do_tree_to_ref(
  tree,
  acc,
) -> #(Exp, set.Set(String), List(#(Exp, set.Set(String)))) {
  case tree {
    e.Variable(label) -> {
      let free = setx.singleton(label)
      #(Var(label), free, acc)
    }
    e.Lambda(label, body) -> {
      let #(node, free, acc) = do_tree_to_ref(body, acc)
      let index = list.length(acc)
      let acc = [#(node, free), ..acc]
      let free = set.delete(free, label)
      #(Fn(label, index), free, acc)
    }
    e.Let(label, value, then) -> {
      let #(then, free_t, acc) = do_tree_to_ref(then, acc)
      let then_index = list.length(acc)
      let acc = [#(then, free_t), ..acc]
      let #(value, free_v, acc) = do_tree_to_ref(value, acc)
      let value_index = list.length(acc)
      let acc = [#(value, free_v), ..acc]

      let free = set.union(free_v, set.delete(free_t, label))
      #(Let(label, value_index, then_index), free, acc)
    }
    e.Binary(value) -> {
      #(String(value), set.new(), acc)
    }
    e.Integer(value) -> {
      #(Integer(value), set.new(), acc)
    }
    _ -> todo("rest of ref")
  }
}

fn tree_to_ref(tree) {
  let #(exp, free, acc) = do_tree_to_ref(tree, [])
  let index = list.length(acc)
  let source = list.reverse([#(exp, free), ..acc])
  #(index, source)
}

fn zip_match(node, path_element) {
  case node, path_element {
    Let(_, index, _), 0 -> index

    Let(_, _, index), 1 -> index
    Fn(_, index), 0 -> index
  }
}

fn do_zip(path, refs, current, zoom, root) {
  case path {
    [] -> #([current, ..zoom], root)
    [path_element, ..path] -> {
      let assert Ok(#(node, _free)) = list.at(refs, current)
      io.debug(node)
      let zoom = [current, ..zoom]
      let current = zip_match(node, path_element)
      do_zip(path, refs, current, zoom, root)
    }
  }
}

// root and refs together from tree
fn zip(path, root, refs) {
  case path {
    [] -> #([], root)
    [path_element, ..path] -> {
      let assert Ok(#(node, _free)) = list.at(refs, root)
      io.debug(node)
      let current = zip_match(node, path_element)
      do_zip(path, refs, current, [], root)
    }
  }
}

pub fn two_test() {
  let tree =
    e.Let(
      "x",
      e.Integer(1),
      e.Let("y", e.Binary("hey"), e.Lambda("p", e.Variable("y"))),
    )

  let #(root, refs) = tree_to_ref(tree)
  io.debug(root)
  io.debug(refs)
  io.debug(list.at(refs, root))

  // binary 
  let path = [1, 0]
  let cursor = zip(path, root, refs)
  io.debug(cursor)
  let [point, ..] = cursor.0
  io.debug(list.at(refs, point))
  let path = [1, 1, 0]
  let cursor = zip(path, root, refs)
  io.debug(cursor)
  let [point, ..] = cursor.0
  io.debug(list.at(refs, point))
}

// TODO printing map in node
// TODO binary-size in JS match