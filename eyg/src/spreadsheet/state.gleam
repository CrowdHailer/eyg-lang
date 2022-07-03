import gleam/io
import gleam/list
import gleam/map

// maybe model or just spreadsheet is a better name

pub type State {
  State(frame: Frame, focus: #(Int, Int))
}

pub type Frame {
  Frame(headers: List(String), data: List(List(String)))
}

pub fn init() {
  let filtered = reduce()
  // TODO derived fields
  let rows =
    list.map(
      filtered,
      fn(entity) {
        assert Ok(StringValue(name)) = map.get(entity, name)
        assert Ok(StringValue(address)) = map.get(entity, address)
        assert Ok(StringValue(stuff)) = map.get(entity, stuff)
        [name, address, stuff]
      },
    )
  State(Frame(["Name", "Address", "Stuff"], rows), #(0, 0))
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

fn reduce() {
  entities(data())
  |> list.filter(map.has_key(_, name))
  |> list.filter(map.has_key(_, address))
  |> io.debug()
}

const name = "Name"

const address = "Address"

const stuff = "Stuff"

fn data() {
  [
    Commit([
      EAV(1, name, StringValue("Alice")),
      EAV(1, address, StringValue("London")),
      // TODO option value for stuff
      EAV(1, stuff, StringValue("")),
      EAV(2, name, StringValue("Bob")),
      EAV(2, address, StringValue("London")),
      EAV(2, stuff, StringValue("Book")),
      EAV(3, name, StringValue("London")),
      EAV(3, "population", IntValue(8000000))
    ]),
    Commit([
      EAV(1, address, StringValue("Leeds")),
    ])
  ]
}

type Commit {
  Commit(changes: List(EAV))
}

type Value {
  StringValue(String)
  IntValue(Int)
}

// Entity Attribute Value
type EAV {
  EAV(entity: Int, attribute: String, value: Value)
}
