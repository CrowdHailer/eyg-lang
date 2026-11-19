import cloud/helpers.{dispatch}
import gleam/dynamic/decode
import gleam/http
import gleam/json
import gleam/string
import wisp/simulate

fn create(context, fields) {
  simulate.request(http.Post, "/boxes")
  |> simulate.json_body(json.object(fields))
  |> dispatch(context)
}

fn write(context, path, contents) {
  simulate.request(http.Put, path)
  |> simulate.string_body(contents)
  |> dispatch(context)
}

fn field(response, name, decoder) {
  let assert Ok(value) =
    json.parse(simulate.read_body(response), decode.at([name], decoder))
  value
}

pub fn create_box_test() {
  use context <- helpers.context()
  let response = create(context, [#("name", json.string("home"))])
  assert 201 == response.status
  assert 1 == field(response, "sequence", decode.int)

  let response = dispatch(simulate.request(http.Get, "/boxes/home"), context)
  assert 200 == response.status
  assert "home" == field(response, "name", decode.string)

  let response =
    dispatch(simulate.request(http.Get, "/boxes/home/files"), context)
  assert "[]" == simulate.read_body(response)
}

pub fn box_names_are_unique_test() {
  use context <- helpers.context()
  assert 201 == create(context, [#("name", json.string("home"))]).status
  assert 409 == create(context, [#("name", json.string("home"))]).status
}

pub fn reject_box_name_test() {
  use context <- helpers.context()
  assert 400 == create(context, [#("name", json.string("My Box"))]).status
}

pub fn missing_box_test() {
  use context <- helpers.context()
  let response = dispatch(simulate.request(http.Get, "/boxes/gone"), context)
  assert 404 == response.status
}

pub fn write_and_read_files_test() {
  use context <- helpers.context()
  let created = create(context, [#("name", json.string("home"))])

  let response = write(context, "/boxes/home/files/notes/todo.txt", "milk")
  assert 200 == response.status
  assert 2 == field(response, "sequence", decode.int)
  assert field(created, "root", decode.string)
    != field(response, "root", decode.string)

  let response =
    simulate.request(http.Get, "/boxes/home/files/notes/todo.txt")
    |> dispatch(context)
  assert "milk" == simulate.read_body(response)

  let response =
    dispatch(simulate.request(http.Get, "/boxes/home/files/notes"), context)
  assert "[{\"name\":\"todo.txt\",\"type\":\"file\",\"size\":4}]"
    == simulate.read_body(response)

  let response =
    simulate.request(http.Delete, "/boxes/home/files/notes")
    |> dispatch(context)
  assert 3 == field(response, "sequence", decode.int)
  assert field(created, "root", decode.string)
    == field(response, "root", decode.string)
}

pub fn reject_invalid_module_test() {
  use context <- helpers.context()
  let created = create(context, [#("name", json.string("home"))])
  assert 200 == write(context, "/boxes/home/files/one.eyg", "1").status

  let response =
    write(context, "/boxes/home/files/main.eyg", "import \"./two.eyg\"")
  assert 422 == response.status
  assert string.contains(field(response, "reason", decode.string), "/main.eyg")

  // Removing a module that is still imported is also rejected.
  let main = "!int_add(1, import \"./one.eyg\")"
  assert 200 == write(context, "/boxes/home/files/main.eyg", main).status
  let response =
    simulate.request(http.Delete, "/boxes/home/files/one.eyg")
    |> dispatch(context)
  assert 422 == response.status

  let response = dispatch(simulate.request(http.Get, "/boxes/home"), context)
  assert 3 == field(response, "sequence", decode.int)
  assert field(created, "root", decode.string)
    != field(response, "root", decode.string)
}

pub fn clone_box_test() {
  use context <- helpers.context()
  let _ = create(context, [#("name", json.string("home"))])
  let _ = write(context, "/boxes/home/files/a.txt", "a")

  let response =
    create(context, [
      #("name", json.string("copy")),
      #("from", json.string("home")),
    ])
  assert 201 == response.status
  assert 1 == field(response, "sequence", decode.int)

  // The boxes change independently.
  let _ = write(context, "/boxes/copy/files/a.txt", "b")
  let response =
    dispatch(simulate.request(http.Get, "/boxes/home/files/a.txt"), context)
  assert "a" == simulate.read_body(response)
  let response =
    dispatch(simulate.request(http.Get, "/boxes/copy/files/a.txt"), context)
  assert "b" == simulate.read_body(response)
}
