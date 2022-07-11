import gleam/io
import gleam/list
import gleam/map
import spreadsheet/log/data.{data}
import spreadsheet/log/reduce

// maybe model or just spreadsheet is a better name

pub type State {
  State(
    commits: List(reduce.Commit),
    focus: #(Int, Int, Int),
    diff: Bool,
    offset: Int,
  )
}

pub fn init() {
  State(data(), #(0, 0, 0), False, 0)
}

// TODO read from a source, though that has no ability to update
// See current changes and make a commit
// map filter reduce
// see lists when joined

// TODO list does a lot of editing

pub fn frame(state: State) {
  let #(table_id, _, _) = state.focus
  // This is a flaky match
  assert Ok([
    [#(_, reduce.StringValue(name))],
    [#(_, reduce.TableRequirements(requirements))],
  ]) = list.at(reduce.tables(state.commits).data, table_id)

  let view = reduce.Table(requirements, [])
  let commits =
    list.take(state.commits, list.length(state.commits) - state.offset)
  let frame = reduce.reduce(commits, view)
  #(name, frame)
}
