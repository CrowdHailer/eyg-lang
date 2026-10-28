import eyg/hub/cache
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import glasshouse/journal
import glasshouse/lock
import glasshouse/recorder
import glasshouse/store
import gleam/dict
import gleam/http
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import loam/execute
import loam/hub_mock
import loam/pin
import loam/record
import loam/sandbox
import loam/source
import loam/system
import multiformats/cid/v1
import ogre/origin

fn state() {
  execute.State(origin.Origin(http.Https, "eyg.run", None), cache.empty())
}

fn parse(code, path) {
  let assert Ok(source) = source.parse(code, source.Disk(path))
  source
}

fn pin_and_record(code, path, sandbox) {
  let source = parse(code, path)
  let recorder = recorder.new(hub_mock.sha256)
  let workflow = {
    use #(pinned, _state, recorder) <- system.then(pin.pin(
      source,
      "/project",
      state(),
      recorder,
      pin.allow,
    ))
    let assert Ok(pinned) = pinned
    use #(outcome, recorder, Nil) <- system.map(record.run_block(
      source,
      [],
      pinned,
      "/project",
      recorder,
      record.computer,
      Nil,
    ))
    #(pinned, outcome, recorder)
  }
  sandbox.run(workflow, sandbox)
}

const main =
  "let helper = import \"./helper.eyg\"
let _ = perform WriteFile({path: \"out.txt\", contents: !string_to_binary(helper.greeting)})
perform ReadFile({path: \"out.txt\", offset: 0, limit: 100})"

fn project() {
  sandbox.sandbox()
  |> sandbox.with_cwd("/project")
  |> sandbox.with_files([
    #("/project/main.eyg", main),
    #("/project/helper.eyg", "{greeting: \"hello\"}"),
  ])
}

pub fn effects_are_recorded_in_order_test() {
  let assert #(sandbox.Returned(#(_, outcome, recorder)), _) =
    pin_and_record(main, "/project/main.eyg", project())
  let assert record.Completed(#(Some(reply), _)) = outcome
  assert reply == v.ok(v.Binary(<<"hello">>))
  let assert [write, read] = recorder.journal(recorder)
  assert write.label == "WriteFile"
  assert write.path == Some("/project/out.txt")
  assert write.answer == journal.Performed
  assert read.label == "ReadFile"
  assert read.path == Some("/project/out.txt")
}

pub fn imports_are_pinned_test() {
  let assert #(sandbox.Returned(#(pinned, _, recorder)), _) =
    pin_and_record(main, "/project/main.eyg", project())
  let assert Ok(lock.File(source:, module:)) =
    dict.get(pinned.lock.files, "/project/helper.eyg")
  let store = recorder.store(recorder)
  assert store.get_binary(store, source) == Ok(<<"{greeting: \"hello\"}">>)
  let assert Ok(_) = store.get_node(store, module)
  // The program refers to the import by content.
  let assert Ok(program) = store.get_node(store, pinned.program)
  let assert Ok(#(helper, _)) = v1.from_string(module)
  assert list.contains(ir.list_references(program), ir.Content(helper))
}

pub fn running_uses_the_pinned_import_test() {
  let source = parse(main, "/project/main.eyg")
  let assert #(sandbox.Returned(#(pinned, _, recorder)), sandbox) =
    pin_and_record(main, "/project/main.eyg", project())
  // The import changes on disk after pinning.
  let sandbox =
    sandbox.with_file(sandbox, "/project/helper.eyg", "{greeting: \"changed\"}")
  let assert #(
    sandbox.Returned(#(record.Completed(#(Some(reply), _)), _, _)),
    _,
  ) =
    record.run_block(
      source,
      [],
      pinned,
      "/project",
      recorder.restart(recorder),
      record.computer,
      Nil,
    )
    |> sandbox.run(sandbox)
  assert reply == v.ok(v.Binary(<<"hello">>))
}

pub fn secret_imports_are_not_stored_test() {
  let sandbox =
    project()
    |> sandbox.with_file("/project/.env.eyg", "{api_key: \"sk-123\"}")
  let code = "let {api_key} = import \"./.env.eyg\"\n!string_length(api_key)"
  let assert #(sandbox.Returned(#(pinned, outcome, recorder)), _) =
    pin_and_record(code, "/project/config.eyg", sandbox)
  let assert record.Completed(#(Some(v.Integer(6)), _)) = outcome
  let assert Ok(lock.File(source: "", module:)) =
    dict.get(pinned.lock.files, "/project/.env.eyg")
  let store = recorder.store(recorder)
  assert !store.has(store, module)
  let everything =
    store.to_list(store)
    |> list.map(fn(entry) { string.inspect(entry.1) })
    |> string.join("")
  assert !string.contains(everything, "sk-123")
}

pub fn import_cycles_are_reported_test() {
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_files([
      #("/p/a.eyg", "import \"./b.eyg\""),
      #("/p/b.eyg", "import \"./a.eyg\""),
    ])
  let source = parse("import \"./a.eyg\"", "/p/main.eyg")
  let assert #(sandbox.Returned(#(Error(reason), _, _)), _) =
    pin.pin(source, "/p", state(), recorder.new(hub_mock.sha256), pin.allow)
    |> sandbox.run(sandbox)
  assert string.contains(reason, "import cycle")
}

pub fn denied_imports_are_reported_test() {
  let deny = fn(_path, state) { system.Done(#(Error(Nil), state)) }
  let source = parse("import \"./a.eyg\"", "/p/main.eyg")
  let assert #(sandbox.Returned(#(Error(reason), _, _)), _) =
    pin.pin(source, "/p", state(), recorder.new(hub_mock.sha256), deny)
    |> sandbox.run(sandbox.sandbox())
  assert reason == "import of /p/a.eyg was denied"
}

fn greeting(message) {
  ir.record([#("message", ir.string(message))])
  |> ir.map_annotation(fn(_) { Nil })
}

pub fn packages_are_pinned_to_the_latest_release_test() {
  let v1_module = greeting("first")
  let v2_module = greeting("second")
  let hub =
    hub_mock.Hub(modules: [v1_module, v2_module], releases: [
      #("greeting", 1, hub_mock.cid(v1_module)),
      #("greeting", 2, hub_mock.cid(v2_module)),
    ])
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_network(fn(r, acc) { hub_mock.handle(r, hub, acc) }, [])
  let code = "@greeting.message"
  let assert #(sandbox.Returned(#(pinned, outcome, recorder)), sandbox) =
    pin_and_record(code, "/project/main.eyg", sandbox)
  let assert record.Completed(#(Some(v.String("second")), _)) = outcome
  assert dict.get(pinned.lock.packages, "greeting")
    == Ok(lock.Release(2, v1.to_string(hub_mock.cid(v2_module))))
  assert store.has(
    recorder.store(recorder),
    v1.to_string(hub_mock.cid(v2_module)),
  )
  // Running again needs no network, a third release changes nothing.
  let source = parse(code, "/project/main.eyg")
  let sandbox =
    sandbox.with_network(
      sandbox,
      fn(r, acc) { #(Error(panic_network(r)), acc) },
      [],
    )
  let assert #(
    sandbox.Returned(#(record.Completed(#(Some(v.String("second")), _)), _, _)),
    _,
  ) =
    record.run_block(
      source,
      [],
      pinned,
      "/project",
      recorder,
      record.computer,
      Nil,
    )
    |> sandbox.run(sandbox)
}

fn panic_network(_request) {
  panic as "no network expected"
}

pub fn versions_are_pinned_test() {
  let v1_module = greeting("first")
  let v2_module = greeting("second")
  let hub =
    hub_mock.Hub(modules: [v1_module, v2_module], releases: [
      #("greeting", 1, hub_mock.cid(v1_module)),
      #("greeting", 2, hub_mock.cid(v2_module)),
    ])
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_network(fn(r, acc) { hub_mock.handle(r, hub, acc) }, [])
  let assert #(sandbox.Returned(#(pinned, outcome, _)), _) =
    pin_and_record("@greeting:1.message", "/project/main.eyg", sandbox)
  let assert record.Completed(#(Some(v.String("first")), _)) = outcome
  assert dict.get(pinned.lock.versions, #("greeting", 1))
    == Ok(v1.to_string(hub_mock.cid(v1_module)))
}

pub fn unknown_package_test() {
  let hub = hub_mock.Hub(modules: [], releases: [])
  let sandbox =
    sandbox.sandbox()
    |> sandbox.with_network(fn(r, acc) { hub_mock.handle(r, hub, acc) }, [])
  let source = parse("@missing", "/project/main.eyg")
  let assert #(sandbox.Returned(#(Error(reason), _, _)), _) =
    pin.pin(
      source,
      "/project",
      state(),
      recorder.new(hub_mock.sha256),
      pin.allow,
    )
    |> sandbox.run(sandbox)
  assert reason == "unknown package @missing"
}

pub fn exit_is_recorded_test() {
  let assert #(sandbox.Returned(#(_, outcome, recorder)), _) =
    pin_and_record("let _ = perform Exit(3)\n1", "/project/main.eyg", project())
  assert outcome == record.Exited(3)
  let assert [exit] = recorder.journal(recorder)
  assert exit.label == "Exit"
}

pub fn unknown_effects_raise_test() {
  let assert #(sandbox.Returned(#(_, outcome, recorder)), _) =
    pin_and_record("perform Unknown(1)", "/project/main.eyg", project())
  let assert record.Raised(_) = outcome
  assert recorder.journal(recorder) == []
}

pub fn requested_path_test() {
  assert record.requested_path("DeleteFile", v.String("a.txt")) == Some("a.txt")
  assert record.requested_path("Now", v.unit()) == None
}
