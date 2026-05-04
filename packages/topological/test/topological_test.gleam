import gleeunit
import topological

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn no_children_test() {
  assert Ok(["B", "A"])
    == [#("A", []), #("B", [])]
    |> topological.sort
}

pub fn self_cycle_test() {
  assert Error(topological.DependencyCycle(["A", "A"]))
    == [#("A", ["A"])]
    |> topological.sort
}

pub fn single_child_test() {
  assert Ok(["A", "B"])
    == [#("A", ["B"]), #("B", [])]
    |> topological.sort
}

pub fn many_child_test() {
  assert Ok(["A", "B", "C", "D"])
    == [#("A", ["B", "C"]), #("B", ["C"]), #("C", ["D"]), #("D", [])]
    |> topological.sort
}

pub fn long_cycle_test() {
  assert Error(topological.DependencyCycle(["A", "B", "C", "D", "A"]))
    == [#("A", ["B", "C"]), #("B", ["C"]), #("C", ["D"]), #("D", ["A"])]
    |> topological.sort
}

pub fn missing_node_test() {
  assert Error(topological.MissingNode("X"))
    == [#("A", ["X"])]
    |> topological.sort
}
