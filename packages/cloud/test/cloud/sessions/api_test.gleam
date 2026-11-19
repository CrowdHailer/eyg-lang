import cloud/helpers.{dispatch}
import gleam/dynamic/decode
import gleam/http
import gleam/json
import gleam/string
import wisp/simulate

fn field(response, name, decoder) {
  let assert Ok(value) =
    json.parse(simulate.read_body(response), decode.at([name], decoder))
  value
}

// The id of a new box.
fn box(context, name) {
  let response =
    simulate.request(http.Post, "/boxes")
    |> simulate.json_body(json.object([#("name", json.string(name))]))
    |> dispatch(context)
  field(response, "id", decode.string)
}

fn session(context, box) {
  let response =
    simulate.request(http.Post, "/boxes/" <> box <> "/sessions")
    |> dispatch(context)
  assert 201 == response.status
  field(response, "id", decode.string)
}

fn turn(context, session, code) {
  let response =
    simulate.request(http.Post, "/sessions/" <> session <> "/turns")
    |> simulate.json_body(json.object([#("code", json.string(code))]))
    |> dispatch(context)
  assert 200 == response.status
  response
}

fn write(path, contents) {
  "perform WriteFile({path: \""
  <> path
  <> "\", contents: !string_to_binary(\""
  <> contents
  <> "\")})"
}

fn root(context, box) {
  dispatch(simulate.request(http.Get, "/boxes/" <> box), context)
  |> field("root", decode.string)
}

pub fn sessions_belong_to_a_box_test() {
  use context <- helpers.context()
  let home = box(context, "home")
  let other = box(context, "other")
  let id = session(context, home)

  let response =
    simulate.request(http.Get, "/boxes/" <> home <> "/sessions")
    |> dispatch(context)
  let assert Ok([found]) =
    json.parse(
      simulate.read_body(response),
      decode.list(decode.at(["id"], decode.string)),
    )
  assert id == found
  let response =
    simulate.request(http.Get, "/boxes/" <> other <> "/sessions")
    |> dispatch(context)
  assert "[]" == simulate.read_body(response)

  let response =
    simulate.request(http.Post, "/boxes/gone/sessions") |> dispatch(context)
  assert 404 == response.status
}

pub fn turns_are_recorded_test() {
  use context <- helpers.context()
  let home = box(context, "home")
  let id = session(context, home)

  let response = turn(context, id, "let _ = perform StandardOut(\"hi\")\n1")
  assert "1" == field(response, "value", decode.string)
  assert ["hi"] == field(response, "output", decode.list(decode.string))
  let response = turn(context, id, "!int_add(1, \"two\")")
  let _ = field(response, "error", decode.string)

  let response =
    dispatch(simulate.request(http.Get, "/sessions/" <> id), context)
  assert home == field(response, "box", decode.string)
  let assert [first, second] =
    field(response, "turns", decode.list(decode.dynamic))
  assert Ok("1") == decode.run(first, decode.at(["value"], decode.string))
  assert Ok(["hi"])
    == decode.run(first, decode.at(["output"], decode.list(decode.string)))
  let assert Ok(_) = decode.run(second, decode.at(["error"], decode.string))
}

pub fn file_changes_are_shared_through_the_box_test() {
  use context <- helpers.context()
  let home = box(context, "home")
  let first = session(context, home)
  let second = session(context, home)

  let _ = turn(context, first, write("/a.txt", "a"))
  let read = "perform ReadFile({path: \"/a.txt\", offset: 0, limit: 10})"
  let response = turn(context, second, read)
  assert string.starts_with(field(response, "value", decode.string), "Ok(")
}

pub fn import_modules_test() {
  use context <- helpers.context()
  let id = session(context, box(context, "home"))
  let _ = turn(context, id, "perform MakeDirectory(\"/lib\")")
  let _ = turn(context, id, write("/lib/one.eyg", "1"))
  let two = "(x) -> { !int_add(x, import \\\"./one.eyg\\\") }"
  let _ = turn(context, id, write("/lib/two.eyg", two))

  // Imports in the code that is run are relative to the root.
  let response = turn(context, id, "let two = import \"lib/two.eyg\"\ntwo(2)")
  assert "3" == field(response, "value", decode.string)
  let response = turn(context, id, "import \"/lib/gone.eyg\"")
  let _ = field(response, "error", decode.string)
}

pub fn reject_write_of_invalid_eyg_test() {
  use context <- helpers.context()
  let home = box(context, "home")
  let before = root(context, home)
  let id = session(context, home)

  let response = turn(context, id, write("/bad.eyg", "let x ="))
  let reason = field(response, "error", decode.string)
  assert string.contains(reason, "/bad.eyg")
  assert before == root(context, home)

  // The same write is accepted when the file is not an EYG module.
  let response = turn(context, id, write("/bad.txt", "let x ="))
  let _ = field(response, "value", decode.string)
  assert before != root(context, home)
}

pub fn failed_code_changes_nothing_test() {
  use context <- helpers.context()
  let home = box(context, "home")
  let before = root(context, home)
  let id = session(context, home)

  let code = write("/a.txt", "a") <> "\n!int_add(1, \"two\")"
  let _ = field(turn(context, id, code), "error", decode.string)
  assert before == root(context, home)
}
