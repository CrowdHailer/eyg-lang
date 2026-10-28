import eyg/interpreter/value as v
import gleam/dict
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import overlay/eval/agent.{Reply}
import overlay/eval/environment
import overlay/eval/evaluate
import overlay/eval/fixture/hub
import overlay/eval/grade
import overlay/eval/judge
import overlay/eval/model
import overlay/eval/module
import overlay/eval/session
import overlay/eval/suite
import overlay/eval/task
import overlay/eval/trial

fn fixtures() {
  let assert Ok(hub) =
    hub.publish_directory(hub.new(), "test/fixtures/packages")
  let assert Ok(suite) = suite.load("test/fixtures/suites/example.eyg", hub)
  let assert Ok(loaded) =
    module.load("test/fixtures/packages/greeting/index.eyg")
  #(environment.Environment(..environment.empty(), hub:), suite, loaded)
}

fn find(suite: suite.Suite, name) {
  let assert Ok(task) = list.find(suite.tasks, fn(task) { task.name == name })
  task
}

pub fn suites_decode_tasks_in_name_order_test() {
  let #(_, suite, _) = fixtures()
  assert "example" == suite.name
  assert ["add", "fact", "greet", "note", "project", "quiet"]
    == list.map(suite.tasks, fn(task) { task.name })

  let add = find(suite, "add")
  assert ["arithmetic"] == add.tags
  assert [task.Computes(v.Integer(5)), task.Says("5")] == add.checks
  assert [[Reply("", ["!int_add(2, 3)"]), Reply("It is 5.", [])]]
    == add.reference
  assert None == add.workspace
  assert task.default_max_model_calls == add.max_model_calls

  let note = find(suite, "note")
  assert Some([#("notes/README.md", <<"# Notes\n">>)]) == note.workspace
  assert 4 == find(suite, "fact").max_model_calls
  let assert [_] = find(suite, "fact").routes
}

pub fn tasks_need_prompts_and_checks_test() {
  let assert Ok(loaded) =
    module.from_source("{nothing: {description: \"x\", prompts: []}}", ".")
  let assert Ok(v.Record(fields)) = evaluate.module(loaded, hub.new())
  let assert Ok(value) = dict.get(fields, "nothing")
  let assert Error(reason) = task.decode("nothing", value)
  assert string.contains(reason, "nothing.")
}

/// A reference solution proves a task can be solved and that its checks
/// recognise a solution.
pub fn oracles_pass_every_deterministic_check_test() {
  let #(environment, suite, loaded) = fixtures()
  let judge =
    model.Scripted(fn(_) { Reply("Ada is greeted.\nVERDICT: PASS", []) })
  list.fold(suite.tasks, promise.resolve(Nil), fn(previous, task) {
    use Nil <- promise.await(previous)
    use trial <- promise.map(trial.run(
      environment,
      session.Module(loaded),
      trial.oracle(task),
      Some(judge),
      task,
      1,
    ))
    list.each(trial.graded, fn(graded) {
      let assert grade.Pass(..) = graded.verdict
    })
    assert trial.passed
    assert 1.0 == trial.score
  })
}

/// An agent that does nothing should never pass, or the checks do not test the
/// task.
pub fn the_null_agent_fails_every_task_test() {
  let #(environment, suite, loaded) = fixtures()
  list.fold(suite.tasks, promise.resolve(Nil), fn(previous, task) {
    use Nil <- promise.await(previous)
    use trial <- promise.map(trial.run(
      environment,
      session.Module(loaded),
      model.Scripted(agent.null()),
      None,
      task,
      1,
    ))
    assert !trial.passed
  })
}

pub fn failures_explain_what_happened_test() {
  let #(environment, suite, loaded) = fixtures()
  let greet = find(suite, "greet")
  let wrong =
    model.Scripted(
      agent.scripted([
        [
          Reply("", ["context.hello(\"Bob\")"]),
          Reply("Open a pull request", []),
        ],
      ]),
    )
  use trial <- promise.map(trial.run(
    environment,
    session.Module(loaded),
    wrong,
    None,
    greet,
    1,
  ))
  let reasons =
    list.map(trial.graded, fn(graded) {
      case graded.verdict {
        grade.Pass(evidence) -> "pass: " <> evidence
        grade.Fail(reason) -> "fail: " <> reason
        grade.Unknown(reason) -> "unknown: " <> reason
      }
    })
  assert [
      "fail: no program references @greeting, no packages were referenced",
      "fail: no program reads context.readme, read: context.hello",
      "pass: run 1 computed a value that starts with Hello",
      "fail: said \"pull request\" in turn 1",
      "unknown: no judge was given for judged checks",
    ]
    == reasons
  assert 0.2 == trial.score
}

pub fn judge_verdicts_are_read_from_the_last_verdict_line_test() {
  let assert judge.Meets(_) = judge.decision("Good.\n**VERDICT: PASS**")
  let assert judge.DoesNotMeet(_) =
    judge.decision("VERDICT: PASS was tempting\nverdict: fail")
  let assert judge.CannotTell(_) = judge.decision("VERDICT: UNKNOWN")
  let assert judge.CannotTell(_) =
    judge.decision("VERDICT: PASSING would be wrong")
  let assert judge.CannotTell(reasoning) = judge.decision("I think it is fine")
  assert string.starts_with(reasoning, "the judge gave no verdict")
}

pub fn context_paths_are_the_longest_reads_test() {
  assert [["libraries", "search"], ["guides"]]
    == grade.context_paths(
      "let found = context.libraries.search(\"json\")
let g = context.guides
found",
    )
  assert [] == grade.context_paths("let context = 1 context")
  assert ["json", "standard"]
    == grade.packages("let a = @json let b = @standard:3.list a")
}
