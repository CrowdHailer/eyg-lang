import gleam/int
import loam/sandbox
import loam/system

pub fn traverse_preserves_effect_and_result_order_test() {
  let workflow = {
    use value <- system.traverse([1, 2, 3])
    use Nil <- system.map(system.stdout(int.to_string(value)))
    value * 2
  }
  let assert #(sandbox.Returned(values), sandbox) =
    sandbox.run(workflow, sandbox.sandbox())
  assert values == [2, 4, 6]
  assert sandbox.stdout == ["3", "2", "1"]
}
