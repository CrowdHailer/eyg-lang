import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/json
import gleam/result
import pal/system

pub fn map_test() {
  assert system.Done(3)
    == system.Done(1)
    |> system.map(int.add(_, 2))

  let assert system.Fetch(_, resume) =
    system.fetch(request.new() |> request.set_body(<<>>))(system.Done)
    |> system.map(fn(response) {
      case response {
        Ok(response.Response(status:, ..)) -> status
        Error(_) -> 0
      }
    })
  assert system.Done(201)
    == resume(Ok(response.new(201) |> response.set_body(<<>>)))
}

pub fn map_request_frame_test() {
  let assert system.RequestFrame(selector: "iframe", timeout: 100, resume:, ..) =
    system.RequestFrame("iframe", json.null(), 100, system.Done)
    |> system.map(fn(reply) { result.is_ok(reply) })
  assert system.Done(False) == resume(Error("No reply"))
}
