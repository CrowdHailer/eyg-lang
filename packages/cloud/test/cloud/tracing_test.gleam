import cloud/beam/execute
import cloud/execute_test
import cloud/test_helpers
import cloud/tracing
import gleam/list
import gleam/option.{None, Some}
import otel/span

fn host() {
  execute.channel_host(
    fn(text) {
      case text {
        "fail" -> Error("refused")
        _ -> Ok("m1")
      }
    },
    execute.no_files(),
    execute.no_triggers(),
    execute.no_schedules(),
    execute.no_artifacts(),
  )
}

/// The spans of one trace, in the order they started.
fn trace(root: tracing.Context) {
  tracing.recent(2000)
  |> list.filter(fn(s: span.Span) { s.trace_id == root.trace_id })
  |> list.reverse
}

fn run(code, policy) {
  let root = tracing.start("test", None, [])
  let context = tracing.context(root)
  let host = execute.Host(..host(), trace: Some(context))
  let _ = execute.run(code, [], policy, host, test_helpers.state())
  tracing.end(root, [], None)
  // The tracer records spans in order, a call returns after every earlier record.
  let _ = tracing.recent(1)
  trace(context)
}

fn attribute(span: span.Span, key) {
  list.key_find(span.attributes, key)
}

pub fn effects_are_spans_inside_the_run_test() {
  let _ = tracing.start_tracer()
  let spans =
    run(
      "let _ = perform Post(\"hi\")\nlet _ = perform Post(\"fail\")\n!int_add(1, 2)",
      execute.unrestricted(),
    )
  let assert [effect, failed, program, root] = spans
  assert root.name == "test"
  assert program.name == "eyg.run"
  assert program.parent_id == Some(root.span_id)
  assert program.error == None
  // Pure computation, the call to int_add, is not traced.
  assert effect.name == "eyg.effect.Post"
  assert effect.parent_id == Some(program.span_id)
  assert attribute(effect, "eyg.policy.decision") == Ok(span.Text("pass"))
  assert effect.error == None
  // An Error reply marks the effect as failed, the program continues.
  assert failed.error == Some("refused")
}

pub fn policy_decisions_are_recorded_test() {
  let _ = tracing.start_tracer()
  let assert Ok(policy) =
    execute.decode_policy(
      execute_test.evaluate(
        "{post: (text) -> { Mock(Ok(\"mocked\")) }, ..cloud.reject_all}",
      ),
      execute_test.state(),
    )
  let assert [mocked, denied, program, _root] =
    run("let _ = perform Post(\"hi\")\nperform Fetch({})", policy)
  assert attribute(mocked, "eyg.policy.decision") == Ok(span.Text("mock"))
  assert denied.name == "eyg.effect.Fetch"
  assert attribute(denied, "eyg.policy.decision")
    == Ok(span.Text("unavailable"))
  assert denied.error == Some("Effect Fetch is not allowed by policy")
  assert program.error == Some("Effect Fetch is not allowed by policy")
}

pub fn headers_test() {
  assert tracing.parse_headers("api-key=a%20b, x=1")
    == [#("api-key", "a b"), #("x", "1")]
}

pub fn session_import_reads_record_their_policy_decisions_test() {
  let _ = tracing.start_tracer()
  let state = execute_test.state()
  let assert Ok(mock) =
    execute.decode_policy(
      execute_test.evaluate(
        "{read_file: (_) -> { Mock(Ok(!string_to_binary(\"42\"))) }, ..cloud.reject_all}",
      ),
      state,
    )
  let assert [read, program, _root] = run("import \"/answer.eyg\"", mock)
  assert read.name == "eyg.effect.ReadFile"
  assert read.parent_id == Some(program.span_id)
  assert attribute(read, "eyg.policy.decision") == Ok(span.Text("mock"))
  assert read.error == None
  assert program.error == None

  let assert Ok(deny) =
    execute.decode_policy(execute_test.evaluate("cloud.reject_all"), state)
  let assert [read, program, _root] = run("import \"/answer.eyg\"", deny)
  assert attribute(read, "eyg.policy.decision") == Ok(span.Text("unavailable"))
  assert read.error == Some("Effect ReadFile is not allowed by policy")
  assert program.error == read.error

  let assert [read, program, _root] =
    run("import \"/answer.eyg\"", execute.unrestricted())
  assert attribute(read, "eyg.policy.decision") == Ok(span.Text("pass"))
  let assert Some(_) = read.error
  assert program.error == read.error
}
