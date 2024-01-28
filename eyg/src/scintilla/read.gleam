import gleam/list
import glance

// The statements fn in glance looks for closing right brace
// glance parses statements assuming a block therefore rename to block
// this finished consuming tokens or errors
fn do_statements(tokens, acc) {
  case glance.statement(tokens) {
    Ok(#(statement, rest)) -> {
      let acc = [statement, ..acc]
      case rest {
        [] -> Ok(list.reverse(acc))
        _ -> do_statements(rest, acc)
      }
    }
    Error(reason) -> Error(reason)
  }
}

pub fn statements(tokens) {
  do_statements(tokens, [])
}
