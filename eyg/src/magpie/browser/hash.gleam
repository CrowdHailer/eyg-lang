import gleam/int
import gleam/list
import gleam/listx
import gleam/result
import gleam/string
import magpie/query
import magpie/store/in_memory.{B, I, L, S}

fn do_index(items, item, count) {
  case items {
    [] -> Error(Nil)
    [i, ..] if i == item -> Ok(count)
    [_, ..rest] -> do_index(rest, item, count + 1)
  }
}

fn index(items, item) {
  do_index(items, item, 0)
}

fn add_match(match, variables) {
  let #(b, v) = case match {
    query.Variable(var) ->
      case index(variables, var) {
        Error(Nil) -> #(string.append("v", var), [var])
        Ok(i) -> #(string.append("r", int.to_string(i)), [])
      }
    query.Constant(c) -> #(
      case c {
        B(True) -> "bt"
        B(False) -> "bf"
        I(i) -> string.append("i", int.to_string(i))
        S(s) -> string.append("s", s)
        L(_) -> panic("list in queries")
      },
      [],
    )
  }
  #(b, list.append(variables, v))
}

fn do_encode_where(patterns, state) {
  case patterns {
    [] -> state
    [#(e, a, v), ..rest] -> {
      let #(parts, variables) = state

      let #(e, variables) = add_match(e, variables)
      let #(a, variables) = add_match(a, variables)
      let #(v, variables) = add_match(v, variables)
      let state = #(list.append(parts, [e, a, v]), variables)
      do_encode_where(rest, state)
    }
  }
}

pub fn encode(queries) {
  list.map(queries, encode_one)
  |> string.join("&")
}

fn encode_one(query) {
  let #(find, where) = query
  let #(where, vars) = do_encode_where(where, #([], []))
  let where = string.join(where, ",")
  let find =
    list.map(find, fn(f) {
      let assert Ok(i) = index(vars, f)
      int.to_string(i)
    })
    |> string.join(",")
  string.concat([where, ":", find])
}

fn do_decode_where(parts, matches, vars) {
  case parts {
    [] -> Ok(#(matches, vars))
    ["v" <> var, ..rest] ->
      do_decode_where(
        rest,
        list.append(matches, [query.Variable(var)]),
        list.append(vars, [var]),
      )
    ["r" <> i, ..rest] -> {
      use i <- result.then(case int.parse(i) {
        Ok(i) -> Ok(i)
        Error(Nil) -> Error("could parse ref as int")
      })
      use var <- result.then(case listx.at(vars, i) {
        Ok(v) -> Ok(v)
        Error(Nil) -> Error("could not find var")
      })
      do_decode_where(rest, list.append(matches, [query.Variable(var)]), vars)
    }
    ["b" <> b, ..rest] -> {
      use b <- result.then(case b {
        "t" -> Ok(True)
        "f" -> Ok(False)
        _ -> Error("not a boolean value")
      })
      do_decode_where(rest, list.append(matches, [query.b(b)]), vars)
    }
    ["i" <> i, ..rest] -> {
      use i <- result.then(case int.parse(i) {
        Ok(i) -> Ok(i)
        Error(Nil) -> Error("not an integer value")
      })
      do_decode_where(rest, list.append(matches, [query.i(i)]), vars)
    }
    ["s" <> s, ..rest] ->
      do_decode_where(rest, list.append(matches, [query.s(s)]), vars)
    _ -> panic("invalid part")
  }
}

fn do_bundle_pattern(parts, patterns) {
  case parts {
    [] -> Ok(list.reverse(patterns))
    [e, a, v, ..rest] -> do_bundle_pattern(rest, [#(e, a, v), ..patterns])
    _ -> Error("not three matches")
  }
}

fn decode_one(str) {
  use #(where, find) <- result.then(case string.split(str, ":") {
    [where, find] -> Ok(#(where, find))
    _ -> Error("incorrect : in hash")
  })
  use #(where, vars) <- result.then(
    case where {
      "" -> []
      _ -> string.split(where, ",")
    }
    |> do_decode_where([], []),
  )
  use where <- result.then(do_bundle_pattern(where, []))
  use find <- result.then(
    case find {
      "" -> []
      _ -> string.split(find, ",")
    }
    |> list.try_map(fn(x) {
      case int.parse(x) {
        Ok(i) -> Ok(i)
        Error(Nil) -> Error("not an int in find value")
      }
    }),
  )
  use find <- result.then(
    list.try_map(find, fn(i) {
      case listx.at(vars, i) {
        Ok(v) -> Ok(v)
        Error(Nil) -> Error("no variable for index")
      }
    }),
  )
  Ok(#(find, where))
}

pub fn decode(str) {
  case str {
    "" -> Ok([])
    _ ->
      string.split(str, "&")
      |> list.try_map(decode_one)
  }
}
