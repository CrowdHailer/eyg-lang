import gleam/list
import gleam/option.{None, Option, Some}

// TODO could be extracted to a path toolkit
// location is separate to path, extract but it may be view layer only.
pub type Location {
  Location(path: List(Int), selection: Option(List(Int)))
}

pub fn open(location) {
  let Location(selection: selection, ..) = location
  case selection {
    None -> False
    Some(_) -> True
  }
}

pub fn focused(location) {
  let Location(selection: selection, ..) = location
  case selection {
    Some([]) -> True
    _ -> False
  }
}

// call location.step
pub fn child(location, i) {
  let Location(path: path, selection: selection) = location
  let path = list.append(path, [i])
  let selection = case selection {
    Some([j, ..inner]) if i == j -> Some(inner)
    _ -> None
  }
  Location(path, selection)
}
