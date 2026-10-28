import eyg/interpreter/value as v
import eyg/ir/tree as ir
import glasshouse/helpers.{sha256}
import glasshouse/journal
import glasshouse/lock
import glasshouse/recorder
import glasshouse/rerun
import glasshouse/run
import glasshouse/secret
import glasshouse/session
import glasshouse/store
import glasshouse/value
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import multiformats/cid/v1

fn nil(node) {
  ir.map_annotation(node, fn(_) { Nil })
}

// let t = perform Now({})
// !int_add(t, 1)
fn now_program() {
  ir.let_(
    "t",
    ir.call(ir.perform("Now"), [ir.unit()]),
    ir.add(ir.variable("t"), ir.integer(1)),
  )
  |> nil
}

fn recorded(program, kind, effects, outcome) {
  let recorder =
    list.fold(effects, recorder.new(sha256), fn(recorder, effect) {
      let #(label, lift, reply) = effect
      recorder.record(
        recorder,
        label,
        lift,
        reply,
        journal.Performed,
        None,
        0,
        0,
      )
    })
  let #(recorder, program) = recorder.store_node(recorder, program)
  let run =
    run.Run(
      id: "r",
      kind:,
      code: "",
      origin: run.Inline,
      program: Some(program),
      lock: lock.empty(),
      cwd: "/",
      journal: recorder.journal(recorder),
      outcome:,
      started: 0,
      ended: 0,
    )
  #(run, recorder.store(recorder))
}

fn rerun(run, store) {
  let #(report, _) = rerun.run(run, store, [], [])
  report
}

pub fn identical_rerun_test() {
  let #(run, store) =
    recorded(
      now_program(),
      run.Block,
      [#("Now", v.unit(), v.Integer(41))],
      run.Returned(value.encode(v.Integer(42))),
    )
  let report = rerun(run, store)
  assert report.problem == None
  assert report.effects == 1
}

pub fn different_result_test() {
  let #(run, store) =
    recorded(
      now_program(),
      run.Block,
      [#("Now", v.unit(), v.Integer(41))],
      run.Returned(value.encode(v.Integer(0))),
    )
  let assert Some(rerun.Different(..)) = rerun(run, store).problem
}

pub fn divergence_test() {
  let #(run, store) =
    recorded(
      now_program(),
      run.Block,
      [#("Random", v.Integer(6), v.Integer(2))],
      run.Returned(value.encode(v.Integer(42))),
    )
  let assert Some(rerun.Diverged(..)) = rerun(run, store).problem
}

pub fn unperformed_effects_test() {
  let #(run, store) =
    recorded(
      now_program(),
      run.Block,
      [#("Now", v.unit(), v.Integer(41)), #("Now", v.unit(), v.Integer(42))],
      run.Returned(value.encode(v.Integer(42))),
    )
  let assert Some(rerun.Diverged(..)) = rerun(run, store).problem
}

pub fn missing_program_test() {
  let #(run, _) = recorded(now_program(), run.Block, [], run.Finished)
  let assert Some(rerun.Unavailable(_)) = rerun(run, store.new()).problem
}

pub fn rejected_runs_are_skipped_test() {
  let #(run, store) =
    recorded(now_program(), run.Block, [], run.Rejected("type error"))
  assert rerun(run, store).problem == None
}

pub fn script_arguments_test() {
  // {script: (args) -> { !list_fold(args, 0, (_, n) -> { !int_add(n, 1) }) }}
  let count =
    ir.call(ir.builtin("list_fold"), [
      ir.variable("args"),
      ir.integer(0),
      ir.func(["_", "n"], ir.add(ir.variable("n"), ir.integer(1))),
    ])
  let program = ir.record([#("script", ir.lambda("args", count))]) |> nil
  let #(run, store) =
    recorded(
      program,
      run.Script(["a", "b"]),
      [],
      run.Returned(value.encode(v.Integer(2))),
    )
  assert rerun(run, store).problem == None
}

pub fn exit_test() {
  let program = ir.call(ir.perform("Exit"), [ir.integer(3)]) |> nil
  let #(run, store) =
    recorded(
      program,
      run.Block,
      [#("Exit", v.Integer(3), v.unit())],
      run.Exited(3),
    )
  assert rerun(run, store).problem == None
}

pub fn modules_resolve_from_the_store_test() {
  let library = ir.record([#("answer", ir.integer(42))]) |> nil
  let #(store, library_id) = store.put_node(store.new(), library, sha256)
  let assert Ok(#(cid, _)) = v1.from_string(library_id)
  let program = #(
    ir.Apply(#(ir.Select("answer"), Nil), #(ir.Reference(ir.Content(cid)), Nil)),
    Nil,
  )
  let #(run, run_store) =
    recorded(program, run.Block, [], run.Returned(value.encode(v.Integer(42))))
  assert rerun(run, store.merge(run_store, store)).problem == None
  let assert Some(rerun.Unavailable(_)) = rerun(run, run_store).problem
}

fn authorized(token) {
  v.Record(dict.from_list([#("authorization", v.String("Bearer " <> token))]))
}

pub fn secrets_are_substituted_test() {
  // let token = match perform MountSecret("github") { Ok(t) -> { t } Error(_) -> { "" } }
  // perform Fetch({authorization: !string_append("Bearer ", token)})
  let program =
    ir.let_(
      "token",
      ir.match(ir.call(ir.perform("MountSecret"), [ir.string("github")]), [
        #("Ok", ir.lambda("t", ir.variable("t"))),
        #("Error", ir.lambda("_", ir.string(""))),
      ]),
      ir.call(ir.perform("Fetch"), [
        ir.record([
          #(
            "authorization",
            ir.call(ir.builtin("string_append"), [
              ir.string("Bearer "),
              ir.variable("token"),
            ]),
          ),
        ]),
      ]),
    )
    |> nil
  let #(run, store) =
    recorded(
      program,
      run.Block,
      [
        #("MountSecret", v.String("github"), v.ok(v.String("ghp_real"))),
        #("Fetch", authorized("ghp_real"), v.ok(v.String("welcome"))),
      ],
      run.Returned(value.encode(v.ok(v.String("welcome")))),
    )
  let secrets = rerun.dummy_secrets(run.journal, store)
  assert list.length(secrets) == 1
  let #(report, _) = rerun.run(run, store, secrets, [])
  assert report.problem == None
  assert report.effects == 2
}

pub fn shell_cells_share_scope_test() {
  // let x = 5
  let first = ir.let_("x", ir.integer(5), ir.vacant()) |> nil
  // !int_add(x, 1)
  let second = ir.add(ir.variable("x"), ir.integer(1)) |> nil
  let #(first, store) = recorded(first, run.Cell, [], run.Finished)
  let #(second, store_2) =
    recorded(second, run.Cell, [], run.Returned(value.encode(v.Integer(6))))
  let session =
    session.Session(
      id: "shell",
      started: 0,
      ended: 0,
      cwd: "/",
      agent: None,
      events: [session.Execution(first), session.Execution(second)],
    )
  let reports = rerun.session(session, store.merge(store, store_2))
  assert list.map(reports, fn(r) { r.problem }) == [None, None]
}

// let token = match perform MountSecret("github") { Ok(t) -> { t } Error(_) -> { "" } }
// perform StandardOut(!int_to_string(!string_length(token)))
fn secret_length_program() {
  ir.let_(
    "token",
    ir.match(ir.call(ir.perform("MountSecret"), [ir.string("github")]), [
      #("Ok", ir.lambda("t", ir.variable("t"))),
      #("Error", ir.lambda("_", ir.string(""))),
    ]),
    ir.call(ir.perform("StandardOut"), [
      ir.call(ir.builtin("int_to_string"), [
        ir.call(ir.builtin("string_length"), [ir.variable("token")]),
      ]),
    ]),
  )
  |> nil
}

pub fn programs_using_a_secret_replay_with_the_real_one_test() {
  let #(run, store) =
    recorded(
      secret_length_program(),
      run.Block,
      [
        #("MountSecret", v.String("github"), v.ok(v.String("ghp_real_token"))),
        #("StandardOut", v.String("14"), v.unit()),
      ],
      run.Returned(value.encode(v.unit())),
    )
  let session =
    session.Session(
      id: "s",
      started: 0,
      ended: 0,
      cwd: "/",
      agent: None,
      events: [session.Execution(run)],
    )
  // A dummy has a different length, the program asks for different output.
  let assert [rerun.Report(problem: Some(rerun.Diverged(..)), ..)] =
    rerun.session(session, store)
  let real = secret.Secret("github", "ghp_real_token")
  let assert [rerun.Report(problem: None, ..)] =
    rerun.session_with_secrets(session, store, [real])
}
