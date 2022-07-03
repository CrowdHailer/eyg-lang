import gleam/io
import gleam/list
import gleam/map
import gleam/option

// maybe model or just spreadsheet is a better name

pub type State {
  State(frame: Frame, focus: #(Int, Int))
}

pub type Frame {
  Frame(headers: List(String), data: List(List(String)))
}

pub fn init() {
  let view =
    Table([
      Requirement(name, StringValue(""), True),
      Requirement(address, StringValue(""), True),
      Requirement(stuff, StringValue(""), False),
    ])

  let frame = reduce(view)
  State(frame, #(0, 0))
}

pub type Requirement {
  Requirement(attribute: String, type_: Value, required: Bool)
}

pub type Table {
  Table(requirements: List(Requirement))
}

// log/data file

fn entities(commits) {
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

fn reduce(view) {
  let rows = list.filter_map(entities(data()), to_view(_, view))
  let headers = list.map(view.requirements, fn(r: Requirement){r.attribute})
  Frame(headers, rows)
}

const name = "Name"

const address = "Address"

const stuff = "Stuff"

fn data() {
  [
    Commit([
      EAV(1, name, StringValue("Alice")),
      EAV(1, address, StringValue("London")),
      EAV(2, name, StringValue("Bob")),
      EAV(2, address, StringValue("London")),
      EAV(2, stuff, StringValue("Book")),
      EAV(3, name, StringValue("London")),
      EAV(3, "population", IntValue(8000000)),
    ]),
    Commit([EAV(1, address, StringValue("Leeds"))]),
  ]
}

pub type Commit {
  Commit(changes: List(EAV))
}

pub type Value {
  StringValue(String)
  IntValue(Int)
}

// Entity Attribute Value
pub type EAV {
  EAV(entity: Int, attribute: String, value: Value)
}
