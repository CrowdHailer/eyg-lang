import eyg/topological as topo
import gleeunit/should

pub fn no_children_test() {
  [#("A", []), #("B", [])]
  |> topo.sort
  |> should.equal(Ok(["B", "A"]))
}

pub fn self_cycle_test() {
  [#("A", ["A"])]
  |> topo.sort
  |> should.equal(Error(topo.DependencyCycle(["A", "A"])))
}

pub fn single_child_test() {
  [#("A", ["B"]), #("B", [])]
  |> topo.sort
  |> should.equal(Ok(["A", "B"]))
}

pub fn many_child_test() {
  [#("A", ["B", "C"]), #("B", ["C"]), #("C", ["D"]), #("D", [])]
  |> topo.sort
  |> should.equal(Ok(["A", "B", "C", "D"]))
}

pub fn long_cycle_test() {
  [#("A", ["B", "C"]), #("B", ["C"]), #("C", ["D"]), #("D", ["A"])]
  |> topo.sort
  |> should.equal(Error(topo.DependencyCycle(["A", "B", "C", "D", "A"])))
}

pub fn missing_node_test() {
  [#("A", ["X"])]
  |> topo.sort
  |> should.equal(Error(topo.MissingNode("X")))
}
