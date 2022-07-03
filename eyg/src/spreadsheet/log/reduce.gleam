import gleam/io
import gleam/list
import gleam/map

pub type Requirement {
  Requirement(attribute: String, type_: Value, required: Bool)
}

// Projection
pub type Table {
  Table(requirements: List(Requirement))
}

pub type Frame {
  Frame(headers: List(String), data: List(List(String)))
}

// log/data file

pub fn entities(commits) {
  list.fold(
    commits,
    map.new(),
    fn(state, commit) {
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
          map.insert(entity, attribute, value)
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
            case type_ {
              StringValue("") -> {
                assert StringValue(value) = value
                Ok(value)
              }
              TableRequirements([]) -> {
                assert TableRequirements(_) = value
                Ok("#Table")
              }
              _ -> todo("something better with values")
            }
          }
          False ->
            case map.get(entity, key) {
              Ok(StringValue(value)) -> Ok(value)
              Error(Nil) -> Ok("")
            }
        }
      },
    )
  Ok(row)
}

pub fn reduce(data, view) {
  let rows = list.filter_map(entities(data), to_view(_, view))
  let headers = list.map(view.requirements, fn(r: Requirement) { r.attribute })
  Frame(headers, rows)
}

pub fn table(commits) {
  let view =
    Table([
      Requirement("name", StringValue(""), True),
      Requirement("requirements", TableRequirements([]), True),
    ])

  reduce(commits, view)
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
