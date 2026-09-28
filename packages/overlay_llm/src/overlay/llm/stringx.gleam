import gleam/list
import gleam/string

pub fn chunk_lines(in) {
  do_chunk_lines(in, [])
}

fn do_chunk_lines(in, acc) {
  case string.split_once(in, "\n") {
    Ok(#(value, rest)) -> do_chunk_lines(rest, [value, ..acc])
    Error(Nil) -> #(list.reverse(acc), in)
  }
}
