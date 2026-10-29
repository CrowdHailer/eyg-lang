import eyg/cli/helpers
import eyg/cli/tui/helpers as h
import eyg/cli/tui/references
import eyg/cli/tui/state
import eyg/hub/cache
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict
import gleam/http/response
import gleam/option.{Some}
import gleam/set
import gleam/string
import loam/execute
import loam/sandbox
import loam/source
import morph/buffer

fn project() {
  sandbox.sandbox()
  |> sandbox.with_cwd("/project")
  |> sandbox.with_file("/project/lib/answer.eyg", "42")
}

fn init() {
  state.init([], h.execute_state())
}

pub fn inserting_an_import_checks_and_queues_it_test() {
  let assert #(state, [_listing]) = h.key(init(), "q")
  let assert #(state, [_listing]) = h.paste(state, "lib/answer.eyg")
  let assert #(state, [read]) = h.key(state, "enter")
  let assert Some(_) = state.buffer.analysis
  assert "◌1 · loading lib/answer.eyg" == h.status_text(state)
  let #(state, _) = h.drain(state, [read], project())
  assert "✔  · Integer" == h.status_text(state)
  assert set.contains(
    state.dependencies,
    references.Import(#(source.Repl, "lib/answer.eyg")),
  )
}

pub fn duplicate_imports_and_navigation_do_not_repeat_io_test() {
  let assert #(state, [read]) =
    h.paste(init(), "[import \"lib/answer.eyg\", import \"lib/answer.eyg\"]")
  assert 1 == set.size(state.dependencies)
  let analysis = state.buffer.analysis
  let assert #(state, []) = h.key(state, "right")
  assert analysis == state.buffer.analysis
  let assert #(state, []) = h.key(state, "left")
  let #(state, _) = h.drain(state, [read], project())
  assert [] == buffer.errors(state.buffer)
}

pub fn missing_imports_change_from_loading_to_errors_test() {
  let assert #(state, [read]) = h.paste(init(), "import \"missing.eyg\"")
  assert "◌1 · loading missing.eyg" == h.status_text(state)
  let #(state, _) = h.drain(state, [read], project())
  assert "!1 · missing reference missing.eyg" == h.status_text(state)
  let assert #(state, []) = h.key(state, "right")
  let assert #(state, [_retry]) = h.paste(state, "import \"missing.eyg\"")
  assert "◌1 · loading missing.eyg" == h.status_text(state)
}

pub fn nested_imports_resolve_from_the_imported_file_test() {
  let serve =
    project()
    |> sandbox.with_file("/project/lib/main.eyg", "import \"answer.eyg\"")
  let assert #(state, [read]) = h.paste(init(), "import \"lib/main.eyg\"")
  let assert #(sandbox.Returned(message), serve) = sandbox.run(read, serve)
  let assert #(state, [nested]) = state.update(state, state.Task(message))
  assert "◌1 · loading lib/main.eyg" == h.status_text(state)
  let #(state, _) = h.drain(state, [nested], serve)
  assert "✔  · Integer" == h.status_text(state)
  assert set.contains(
    state.dependencies,
    references.Import(#(source.Disk("/project/lib/main.eyg"), "answer.eyg")),
  )
}

pub fn cyclic_imports_finish_as_errors_test() {
  let serve =
    project()
    |> sandbox.with_files([
      #("/project/a.eyg", "import \"b.eyg\""),
      #("/project/b.eyg", "import \"a.eyg\""),
    ])
  let #(state, effects) = h.paste(init(), "import \"a.eyg\"")
  let #(state, _) = h.drain(state, effects, serve)
  assert "!1 · missing reference a.eyg" == h.status_text(state)
}

pub fn imports_are_checked_in_a_pure_empty_scope_test() {
  let serve =
    project()
    |> sandbox.with_file("/project/bad.eyg", "perform StandardOut(\"hi\")")
  let #(state, effects) = h.paste(init(), "import \"bad.eyg\"")
  let #(state, _) = h.drain(state, effects, serve)
  assert "!1 · missing reference bad.eyg" == h.status_text(state)
}

fn with_package(module) {
  let cid = helpers.cid_from_tree(module)
  let execute = h.execute_state()
  let cache =
    cache.Cache(
      ..execute.cache,
      packages: dict.from_list([#("demo", cache.Entry(1, cid, 1, 1, cid))]),
      releases: dict.from_list([#(#("demo", 1), cid)]),
    )
  state.init([], execute.State(..execute, cache:))
}

pub fn imports_and_releases_load_in_the_same_check_test() {
  let module = ir.integer(9)
  let assert #(state, [fetch, read]) =
    h.paste(with_package(module), "[import \"lib/answer.eyg\", @demo:1]")
  assert string.starts_with(h.status_text(state), "◌2 ")
  let #(state, serve) = h.drain(state, [read], project())
  assert string.starts_with(h.status_text(state), "◌1 ")
  let serve =
    sandbox.save_and_return(
      serve,
      response.new(200) |> response.set_body(dag_json.to_block(module)),
    )
  let #(state, _) = h.drain(state, [fetch], serve)
  assert "✔  · List(Integer)" == h.status_text(state)
  assert set.contains(state.dependencies, references.Hub(ir.Version("demo", 1)))
}

pub fn a_missing_package_does_not_pull_forever_test() {
  let assert #(state, [_pull]) = h.paste(init(), "@missing")
  assert "◌1 · loading @missing" == h.status_text(state)
  let assert #(state, []) =
    state.update(
      state,
      state.Task(state.CacheUpdated(cache.PullPackagesCompleted(Ok([])))),
    )
  assert "!1 · missing reference @missing" == h.status_text(state)
}

pub fn a_new_release_dependency_discovered_in_a_file_is_queued_test() {
  let serve = project() |> sandbox.with_file("/project/main.eyg", "@missing")
  let assert #(state, [read]) = h.paste(init(), "import \"main.eyg\"")
  let assert #(sandbox.Returned(message), _) = sandbox.run(read, serve)
  let assert #(state, [_pull]) = state.update(state, state.Task(message))
  assert "◌1 · loading main.eyg" == h.status_text(state)
  let assert #(state, []) =
    state.update(
      state,
      state.Task(state.CacheUpdated(cache.PullPackagesCompleted(Ok([])))),
    )
  assert "!1 · missing reference main.eyg" == h.status_text(state)
}

pub fn finishing_a_picker_uses_types_loaded_while_it_was_open_test() {
  let assert #(state, [read]) = h.paste(init(), "import \"lib/answer.eyg\"")
  let assert #(state, [_listing]) = h.key(state, "q")
  let #(state, _) = h.drain(state, [read], project())
  let assert #(state, [_listing]) = h.paste(state, "lib/answer.eyg")
  let assert #(state, []) = h.key(state, "enter")
  assert "✔  · Integer" == h.status_text(state)
}

pub fn a_failed_fetch_is_retried_on_edit_not_on_navigation_test() {
  let assert #(state, [fetch]) = h.paste(with_package(ir.integer(9)), "@demo")
  let serve =
    sandbox.sandbox()
    |> sandbox.save_and_return(response.new(404) |> response.set_body(<<>>))
  let #(state, _) = h.drain(state, [fetch], serve)
  assert "!1 · missing reference @demo" == h.status_text(state)
  let assert #(state, []) = h.key(state, "right")
  let assert #(state, [_fetch]) = h.paste(state, "@demo")
  assert "◌1 · loading @demo" == h.status_text(state)
}
