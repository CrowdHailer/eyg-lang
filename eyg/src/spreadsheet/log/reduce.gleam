import gleam/io
import gleam/list
import gleam/map

pub type Requirement {
  Requirement(attribute: String, type_: Value, required: Bool)
}

// Projection
pub type Table {
  Table(requirements: List(Requirement), derived: List(#(String, fn(Nil) -> Nil)))
  
}

// TODO
// Just write functions for filter
// Can we prove canonical tree? in which case we can test for stability by writing the tree we want and checking it doesn't change
// Test to find all the commits that affected a projection



pub type Frame {
  Frame(
    commit: Int,
    headers: List(String),
    data: List(List(List(#(Int, Value)))),
  )
}

// log/data file

pub fn entities(commits) {
  list.index_fold(
    commits,
    map.new(),
    fn(state, commit, index) {
      let Commit(changes) = commit
      list.fold(
        changes,
        state,
        fn(state, change) {
          let EAV(entity_id, attribute, value) = change
          let entity = case map.get(state, entity_id) {
            Ok(e) -> e
            Error(Nil) -> map.new()
          }
          let history = case map.get(entity, attribute) {
            Error(Nil) -> []
            Ok(history) -> history
          }
          map.insert(entity, attribute, [#(index, value), ..history])
          |> map.insert(state, entity_id, _)
        },
      )
    },
  )
  |> map.values()
}

fn to_view(entity, view: Table) {
  try row =
    list.try_map(
      view.requirements,
      fn(column) {
        let Requirement(key, type_, required) = column
        case required {
          True -> {
            try value = map.get(entity, key)
            Ok(value)
          }
          False ->
            case map.get(entity, key) {
              Ok(value) -> Ok(value)
              Error(Nil) -> Ok([])
            }
        }
      },
    )
  Ok(row)
}

pub fn tables(commits) {
  let requirements = [
    Requirement("name", StringValue(""), True),
    Requirement("requirements", TableRequirements([]), True),
  ]
  let zero =
    Commit([
      EAV(0, "name", StringValue("tables")),
      EAV(0, "requirements", TableRequirements(requirements)),
    ])
  reduce(commits, Table(requirements, []))
}

pub fn reduce(data, view) {
  let requirements = [
    Requirement("name", StringValue(""), True),
    Requirement("requirements", TableRequirements([]), True),
  ]
  let zero =
    Commit([
      EAV(0, "name", StringValue("tables")),
      EAV(0, "requirements", TableRequirements(requirements)),
    ])
  let count = list.length(data)
  let data = [zero, ..data]
  let rows = list.filter_map(entities(data), to_view(_, view))
  let headers = list.map(view.requirements, fn(r: Requirement) { r.attribute })
  Frame(count, headers, rows)
}

pub type Commit {
  Commit(changes: List(EAV))
}

pub type Value {
  StringValue(String)
  IntValue(Int)
  TableRequirements(List(Requirement))
}

// Entity Attribute Value
pub type EAV {
  EAV(entity: Int, attribute: String, value: Value)
}
