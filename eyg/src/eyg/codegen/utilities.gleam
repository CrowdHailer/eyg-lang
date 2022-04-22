import gleam/list
import gleam/string

pub fn indent(lines) {
  list.map(lines, fn(line) { string.concat(["  ", line]) })
}

pub fn wrap_lines(pre, lines, post) {
  case lines {
    [] -> [string.concat([pre, post])]
    [first, ..rest] -> {
      let first = string.concat([pre, first])
      let lines = [first, ..rest]
      let [last, ..rest] = list.reverse(lines)
      let last = string.concat([last, post])
      list.reverse([last, ..rest])
    }
  }
}

pub fn squash(a, b) {
  let [pre, ..a] = list.reverse(a)
  let [post, ..b] = b
  list.append(list.reverse(a), [string.concat([pre, post]), ..b])
}

pub fn wrap_single_or_multiline(terms, delimeter, before, after) {
  let grouped =
    list.fold(
      terms,
      Ok([]),
      fn(state, lines) {
        case state {
          Ok(singles) ->
            case lines {
              [single] -> Ok([single, ..singles])
              multi -> {
                let previous = list.map(singles, fn(s) { [s] })
                Error([multi, ..previous])
              }
            }
          Error(multis) -> Error([lines, ..multis])
        }
      },
    )
  case grouped {
    Ok(singles) -> {
      let values_string =
        singles
        |> list.reverse()
        |> list.intersperse(string.concat([delimeter, " "]))
        |> wrap_lines(before, _, after)
        |> string.concat()
      [values_string]
    }
    Error(multis) -> {
      let lines =
        multis
        |> list.reverse()
        |> list.map(wrap_lines("", _, delimeter))
        |> list.flatten()
        |> indent()
      let lines =
        [before]
        |> list.append(lines)
        |> list.append([after])
      lines
    }
  }
}
