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
  // TODO this needs to work on entity_id
  // and return entities ordered by that
  assert Ok(entity) = list.at(reduce.entities(state.commits), table_id)
  // assert Ok(reduce.StringValue(name)) = map.get(entity, "name")
  assert Ok(reduce.TableRequirements(requirements)) =
    map.get(entity, "requirements")
  let view = reduce.Table(requirements)

  // Add table of tables to the front
  let frame = reduce.reduce(state.commits, view)
}
