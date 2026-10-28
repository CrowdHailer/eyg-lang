//// Run with `gleam run -m loam/sandbox_bench --target javascript --runtime bun`.
//// Retains every fork and checks actual sharing, rather than timing allocation
//// of empty machines that the garbage collector could immediately discard.

import eyg/interpreter/process
import eyg/interpreter/value as v
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import loam/environment
import loam/execute
import loam/sandbox
import loam/sandbox/fs
import loam/source
import loam/virtual

import plinthx/browser/performance
import plinthx/bun/runtime
import plinthx/javascript/object
import plinthx/node/process as native_process

fn heap_bytes() {
  let assert Ok(p) = native_process.get()
  native_process.heap_bytes(p)
}

fn milliseconds() {
  let assert Ok(p) = performance.get()
  performance.now(p)
}

fn same(a, b) {
  object.is_same(a, b)
}

fn collect() {
  let assert Ok(bun) = runtime.get()
  runtime.collect(bun, True)
}

pub fn main() {
  let count = 1000
  let bytes = 4 * 1024 * 1024
  let fixture =
    sandbox.sandbox()
    |> sandbox.with_file("/workspace/shared", string.repeat("x", bytes))
  let environment =
    environment.Environment(..environment.new(), files: fixture.file_system)
  let state = environment.execution_state(environment, environment.hub)
  let assert Ok(node) =
    source.parse(
      "perform WriteFile({path: \"private\", contents: !string_to_binary(\"one fork\")})",
      source.Inline,
    )
  let assert Ok(shared) = fs.inspect(environment.files, "/workspace/shared")
  collect()
  let before = heap_bytes()
  let started = milliseconds()
  let forks =
    list.repeat(Nil, count)
    |> list.map(fn(_) {
      let machine = virtual.fork(environment)
      let assert #(sandbox.Returned(#(Ok(_), machine)), _) =
        virtual.run(execute.block(node, [], state), machine)
        |> sandbox.run(sandbox.sandbox())
      machine
    })
  let elapsed = milliseconds() -. started
  collect()
  let retained = heap_bytes() - before
  let sharing =
    list.all(forks, fn(machine) {
      let assert Ok(file) = fs.inspect(machine.file_system, "/workspace/shared")
      same(file, shared)
      && fs.read(machine.file_system, "/workspace/private") == Ok("one fork")
    })
  assert sharing
  let assert Error(_) = fs.read(environment.files, "/workspace/private")
  let assert Ok(infinite) =
    source.parse("!fix((self, x) -> { self(x) })(0)", source.Inline)
  let assert Ok(finite) = source.parse("42", source.Inline)
  let assert process.Yielded(_) =
    process.slice(process.start(infinite, []), 100)
  let assert process.Returned(Some(v.Integer(42)), _) =
    process.slice(process.start(finite, []), 100)
  io.println(
    json.to_string(
      json.object([
        #("forks", json.int(count)),
        #("shared_input_bytes", json.int(bytes)),
        #("same_input_object_in_every_fork", json.bool(sharing)),
        #("elapsed_ms", json.float(elapsed)),
        #("retained_heap_delta_bytes", json.int(retained)),
        #("retained_heap_delta_per_fork", json.int(retained / count)),
        #("runaway_yielded", json.bool(True)),
      ]),
    ),
  )
}
