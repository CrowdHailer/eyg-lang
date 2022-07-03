import gleam/io
import gleam/list
import gleam/map
import spreadsheet/log/data.{data}
import spreadsheet/log/reduce

// maybe model or just spreadsheet is a better name

pub type State {
  State(commits: List(reduce.Commit), focus: #(Int, Int, Int))
}

pub fn init() {
  State(data(), #(0, 0, 0))
}

pub fn frame(state: State) {
  let #(table_id, _, _) = state.focus
  // This is a flaky match
  assert Ok([reduce.StringValue(_), reduce.TableRequirements(requirements)]) =
    list.at(reduce.tables(state.commits).data, table_id)

  let view = reduce.Table(requirements)
  let frame = reduce.reduce(state.commits, view)
}
