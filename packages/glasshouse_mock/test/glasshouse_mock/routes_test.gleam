import glasshouse/langfuse as export
import glasshouse_mock
import glasshouse_mock/langfuse
import glasshouse_mock/langfuse_test
import glasshouse_mock/model
import glasshouse_mock/neon
import gleam/bit_array
import gleam/crypto
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/string

fn state() {
  let assert Ok(rules) =
    model.parse(
      "{\"rules\": [{\"prompt\": \"\", \"steps\": [{\"text\": \"Hi.\"}]}]}",
    )
  let assert Ok(database) =
    neon.seed(neon.new(), "create table todos (title text)", 1000)
  glasshouse_mock.State(traces: langfuse.new(), rules:, database:)
}

const credentials = "Basic cGstbGYtbG9jYWw6c2stbGYtbG9jYWw="

fn send(state, request) {
  let #(state, response) = glasshouse_mock.handle(state, request, 2000)
  let assert Ok(body) = bit_array.to_string(response.body)
  #(state, response, body)
}

fn get(path) {
  request.new() |> request.set_path(path) |> request.set_body(<<>>)
}

fn upload(state) {
  let #(session, store) = langfuse_test.session()
  let body =
    export.payload(session, store, crypto.hash(crypto.Sha256, _))
    |> json.to_string
  request.new()
  |> request.set_method(http.Post)
  |> request.set_path("/api/public/otel/v1/traces")
  |> request.set_header("authorization", credentials)
  |> request.set_body(<<body:utf8>>)
  |> send(state, _)
}

pub fn uploaded_traces_can_be_read_back_test() {
  let #(state, response, _) = upload(state())
  assert response.status == 200
  let #(_, response, body) =
    get("/api/public/traces")
    |> request.set_header("authorization", credentials)
    |> send(state, _)
  assert response.status == 200
  assert string.contains(body, "\"sessionId\":\"20261013T110100-abcd\"")
  let #(session, _) = langfuse_test.session()
  let id = export.trace_id(session, crypto.hash(crypto.Sha256, _))
  let #(_, response, body) =
    get("/api/public/traces/" <> id)
    |> request.set_header("authorization", credentials)
    |> send(state, _)
  assert response.status == 200
  assert string.contains(body, "\"type\":\"GENERATION\"")
}

pub fn the_api_needs_credentials_test() {
  let #(state, response, _) = upload(state())
  assert response.status == 200
  let #(_, response, _) = send(state, get("/api/public/traces"))
  assert response.status == 401
}

pub fn traces_are_shown_as_pages_test() {
  let #(state, _, _) = upload(state())
  let #(_, response, body) = send(state, get("/"))
  assert response.status == 200
  assert string.contains(body, "overlay session")
  let #(session, _) = langfuse_test.session()
  let id = export.trace_id(session, crypto.hash(crypto.Sha256, _))
  let #(_, response, body) = send(state, get(export.trace_url("", id)))
  assert response.status == 200
  assert string.contains(body, "Hello there.")
  let #(_, response, _) = send(state, get("/trace/missing"))
  assert response.status == 404
}

pub fn the_model_answers_chat_requests_test() {
  let body =
    "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}"
  let #(_, response, body) =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_path("/api/chat")
    |> request.set_body(<<body:utf8>>)
    |> send(state(), _)
  assert response.status == 200
  assert string.contains(body, "\"content\":\"Hi.\"")
}

pub fn queries_change_the_database_page_test() {
  let request =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_path("/sql")
    |> request.set_header(
      "neon-connection-string",
      "postgresql://demo:demo@localhost:4400/demo",
    )
    |> request.set_body(<<
      {
        json.to_string(
          json.object([
            #(
              "query",
              json.string("insert into todos values ('write the guide')"),
            ),
            #("params", json.preprocessed_array([])),
          ]),
        )
      }:utf8,
    >>)
  let #(state, response, _) = send(state(), request)
  assert response.status == 200
  let #(_, _, body) = send(state, get("/neon"))
  assert string.contains(body, "write the guide")
  assert list.length(state.database) == 2
}

pub fn browsers_may_call_the_mock_test() {
  let #(_, response, _) =
    get("/api/chat") |> request.set_method(http.Options) |> send(state(), _)
  assert response.status == 204
  assert response.get_header(response, "access-control-allow-origin") == Ok("*")
}

pub fn unknown_paths_are_not_found_test() {
  let #(_, response, _) = send(state(), get("/nothing/here"))
  assert response.status == 404
}
