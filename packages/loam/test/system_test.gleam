import gleam/int
import gleam/option.{None, Some}
import loam/sandbox
import loam/system
import loam/virtual
import simplifile

pub fn keys_are_ordered_and_empty_reads_advance_virtual_time_test() {
  let workflow = {
    use first <- system.then(system.read_key(50))
    use second <- system.then(system.read_key(50))
    use none <- system.map(system.read_key(50))
    #(first, second, none)
  }
  let input =
    sandbox.sandbox()
    |> sandbox.with_keys(["ArrowUp", "q"])
    |> sandbox.with_now(1000)
  let assert #(sandbox.Returned(keys), result) = sandbox.run(workflow, input)
  assert keys == #(Some("ArrowUp"), Some("q"), None)
  assert result.now == 1050
  let machine = virtual.new("/", 1000, 1) |> virtual.with_keys(["ArrowUp", "q"])
  let assert system.Done(#(Ok(keys), result)) = virtual.run(workflow, machine)
  assert keys == #(Some("ArrowUp"), Some("q"), None)
  assert result.clock == 1050
}

pub fn resolve_relative_paths_test() {
  assert system.resolve_relative("/project/src", "../data/./file")
    == Ok("/project/data/file")
  assert system.resolve_relative("/project/src", "/other/file")
    == Ok("/other/file")
  assert system.resolve_relative("src", "../data/file") == Ok("data/file")
  // assert system.resolve_relative("/project", "data/") == Ok("/project/data/")
  assert system.resolve_relative("/project", "../") == Ok("/")
  assert system.resolve_relative("src", "../") == Ok("")
}

pub fn unresolvable_paths_are_invalid_arguments_test() {
  assert system.resolve_relative("/project", "../../file")
    == Error(simplifile.Einval)
  assert system.resolve_relative("/project", "/../file")
    == Error(simplifile.Einval)
  assert system.resolve_relative("src", "../../file")
    == Error(simplifile.Einval)
}

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

pub fn explicit_spans_preserve_sandbox_effects_and_results_test() {
  let workflow =
    system.span(
      "workflow",
      [#("task", "test")],
      fn() {
        use Nil <- system.then(system.stdout("before"))
        use result <- system.then(
          system.span(
            "lookup",
            [],
            fn() { system.Done(Error("missing")) },
            fn(result) {
              case result {
                Ok(_) -> None
                Error(message) -> Some(message)
              }
            },
          ),
        )
        use Nil <- system.map(system.stdout("after"))
        result
      },
      fn(_) { None },
    )
  let assert #(sandbox.Returned(result), sandbox) =
    sandbox.run(workflow, sandbox.sandbox())
  assert result == Error("missing")
  assert sandbox.stdout == ["after", "before"]
}

pub fn exit_inside_explicit_span_preserves_status_test() {
  let workflow =
    system.span("exit", [], fn() { system.Exit(7) }, fn(_) { None })
  let assert #(sandbox.Exited(status), _) =
    sandbox.run(workflow, sandbox.sandbox())
  assert status == 7
}
