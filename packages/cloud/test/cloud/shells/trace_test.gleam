import cloud/beam/execute
import cloud/helpers
import cloud/server
import cloud/shell_helpers
import cloud/shells/event
import cloud/shells/trace.{Span}
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import howdy/testing as simulate
import unixfs/mfs

pub fn spans_from_entries_test() {
  let root = mfs.identify(mfs.Directory([])).cid
  let get =
    request.new() |> request.set_host("example.com") |> request.set_body(<<>>)
  let post = request.set_method(get, http.Post)
  let fetched =
    execute.Fetched(Ok(response.new(200) |> response.set_body(<<>>)))
  let log = [
    #(10, event.Input(event.Started("a", root), 1, root)),
    #(12, event.Output([], event.Requested(get), root, event.Unchanged)),
    #(20, event.Input(event.Continued(fetched), 1, root)),
    #(22, event.Output([], event.Finished(Ok("1"), []), root, event.Unchanged)),
    #(30, event.Input(event.Started("b", root), 1, root)),
    #(32, event.Output([], event.Requested(post), root, event.Unchanged)),
  ]
  let assert [shell, a, request_a, b, request_b] = trace.spans("s", log)
  assert Span(..shell, id: "")
    == Span("", None, "shell", False, 10, 32, [#("shell.id", "s")], None)
  assert Some(shell.id) == a.parent
  assert #("turn", 10, 22, None) == #(a.name, a.start, a.end, a.error)
  assert Some(a.id) == request_a.parent
  assert #("GET", True, 12, 20, None)
    == #(
      request_a.name,
      request_a.client,
      request_a.start,
      request_a.end,
      request_a.error,
    )
  assert list.contains(request_a.attributes, #(
    "http.response.status_code",
    "200",
  ))
  assert list.contains(request_a.attributes, #(
    "url.full",
    "https://example.com",
  ))
  assert #(30, 32, Some("unfinished")) == #(b.start, b.end, b.error)
  // The request was never answered, the shell stopped while waiting.
  assert Some(b.id) == request_b.parent
  assert #("POST", Some("no response was recorded"))
    == #(request_b.name, request_b.error)
  assert list.unique([shell.id, a.id, request_a.id, b.id, request_b.id])
    |> list.length
    == 5
}

pub fn no_entries_no_spans_test() {
  assert [] == trace.spans("s", [])
}

pub fn trace_a_shell_test() {
  use context <- helpers.context()
  let shell = shell_helpers.shell(context)
  let server = server.start(process.new_subject())
  let assert Ok(_) =
    shell_helpers.run(context, shell, server.fetch(server, "GET", "/hello"))
  let response =
    simulate.request(http.Get, "/shells/" <> shell.id <> "/trace")
    |> helpers.dispatch(context)
  assert 200 == response.status
  let span = {
    use name <- decode.field("name", decode.string)
    use trace <- decode.field("traceId", decode.string)
    use start <- decode.field("startTimeUnixNano", decode.string)
    use end <- decode.field("endTimeUnixNano", decode.string)
    let assert Ok(start) = int.parse(start)
    let assert Ok(end) = int.parse(end)
    decode.success(#(name, trace, start, end))
  }
  let spans =
    decode.list(decode.at(["spans"], decode.list(span)))
    |> decode.at(["scopeSpans"], _)
    |> decode.list
    |> decode.at(["resourceSpans"], _)
  let assert Ok([[[shell, turn, request]]]) =
    json.parse(simulate.text(response), spans)
  assert #("shell", "turn", "GET") == #(shell.0, turn.0, request.0)
  assert shell.1 == turn.1 && shell.1 == request.1
  // Each span is inside its parent and the request took some time.
  assert shell.2 <= turn.2 && turn.2 < request.2
  assert request.2 < request.3
  assert request.3 < turn.3 && turn.3 <= shell.3
}
