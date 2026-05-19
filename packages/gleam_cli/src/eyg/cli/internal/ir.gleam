import eyg/cli/internal/source
import eyg/ir/tree as ir
import gleam/list

pub const meta = source.Location(source.Repl, source.Json)

pub fn string(s) {
  #(ir.String(s), meta)
}

pub fn list(items) {
  do_list(list.reverse(items), tail())
}

pub fn do_list(reversed, acc) {
  case reversed {
    [item, ..rest] -> do_list(rest, apply(apply(cons(), item), acc))
    [] -> acc
  }
}

pub fn tail() {
  #(ir.Tail, meta)
}

pub fn cons() {
  #(ir.Cons, meta)
}

pub fn apply(func, argument) {
  #(ir.Apply(func, argument), meta)
}

pub fn unit() {
  #(ir.Empty, meta)
}

pub fn select(label) {
  #(ir.Select(label), meta)
}
