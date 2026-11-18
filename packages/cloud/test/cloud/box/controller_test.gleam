import cloud/helpers.{dispatch}
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None}
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

fn id(response) {
  field(response, "id", decode.string)
}

pub fn create_box_test() {
  use context <- helpers.context()
  let response = create(context, [#("name", json.string("home"))])
  assert 201 == response.status
  assert 1 == field(response, "sequence", decode.int)
  let home = "/boxes/" <> id(response)

  let response = dispatch(simulate.request(http.Get, home), context)
  assert 200 == response.status
  assert "home" == field(response, "name", decode.string)

  let response = dispatch(simulate.request(http.Get, home <> "/files"), context)
  // A new box starts with its configuration and the skill for writing skills.
  assert "[{\"name\":\"_box\",\"type\":\"directory\"},{\"name\":\"skills\",\"type\":\"directory\"}]"
    == simulate.read_body(response)
  let response =
    simulate.request(http.Get, home <> "/files/skills/writing-skills/SKILL.md")
    |> dispatch(context)
  assert string.starts_with(
    simulate.read_body(response),
    "---\nname: writing-skills\n",
  )
}

pub fn list_named_boxes_test() {
  use context <- helpers.context()
  let home = id(create(context, [#("name", json.string("home"))]))
  // A box without a name is transient, it is not listed.
  let response = create(context, [#("from", json.string(home))])
  assert 201 == response.status
  let transient = id(response)
  assert None == field(response, "name", decode.optional(decode.string))

  // Other tests leave named boxes behind.
  let response = dispatch(simulate.request(http.Get, "/boxes"), context)
  let assert Ok(listed) =
    json.parse(
      simulate.read_body(response),
      decode.list(decode.at(["id"], decode.string)),
    )
  assert list.contains(listed, home)
  assert !list.contains(listed, transient)
}

pub fn box_names_are_unique_test() {
  use context <- helpers.context()
  assert 201 == create(context, [#("name", json.string("home"))]).status
  assert 409 == create(context, [#("name", json.string("home"))]).status
}

pub fn reject_box_name_test() {
  use context <- helpers.context()
  assert 422 == create(context, [#("name", json.string("My Box"))]).status
}

pub fn missing_box_test() {
  use context <- helpers.context()
  let response = dispatch(simulate.request(http.Get, "/boxes/gone"), context)
  assert 404 == response.status
}

pub fn write_and_read_files_test() {
  use context <- helpers.context()
  let created = create(context, [#("name", json.string("home"))])
  let home = "/boxes/" <> id(created)

  let response = write(context, home <> "/files/notes/todo.txt", "milk")
  assert 200 == response.status
  assert 2 == field(response, "sequence", decode.int)
  assert field(created, "root", decode.string)
    != field(response, "root", decode.string)

  let response =
    simulate.request(http.Get, home <> "/files/notes/todo.txt")
    |> dispatch(context)
  assert "milk" == simulate.read_body(response)

  let response =
    dispatch(simulate.request(http.Get, home <> "/files/notes"), context)
  assert "[{\"name\":\"todo.txt\",\"type\":\"file\",\"size\":4}]"
    == simulate.read_body(response)

  let response =
    simulate.request(http.Delete, home <> "/files/notes")
    |> dispatch(context)
  assert 3 == field(response, "sequence", decode.int)
  assert field(created, "root", decode.string)
    == field(response, "root", decode.string)
}

pub fn reject_invalid_module_test() {
  use context <- helpers.context()
  let created = create(context, [#("name", json.string("home"))])
  let home = "/boxes/" <> id(created)
  assert 200 == write(context, home <> "/files/one.eyg", "1").status

  let response =
    write(context, home <> "/files/main.eyg", "import \"./two.eyg\"")
  assert 422 == response.status
  assert string.contains(field(response, "reason", decode.string), "/main.eyg")

  // Removing a module that is still imported is also rejected.
  let main = "!int_add(1, import \"./one.eyg\")"
  assert 200 == write(context, home <> "/files/main.eyg", main).status
  let response =
    simulate.request(http.Delete, home <> "/files/one.eyg")
    |> dispatch(context)
  assert 422 == response.status

  let response = dispatch(simulate.request(http.Get, home), context)
  assert 3 == field(response, "sequence", decode.int)
  assert field(created, "root", decode.string)
    != field(response, "root", decode.string)
}

pub fn clone_box_test() {
  use context <- helpers.context()
  let home = id(create(context, [#("name", json.string("home"))]))
  let _ = write(context, "/boxes/" <> home <> "/files/a.txt", "a")

  let response =
    create(context, [
      #("name", json.string("copy")),
      #("from", json.string(home)),
    ])
  assert 201 == response.status
  assert 1 == field(response, "sequence", decode.int)
  let copy = id(response)

  // The boxes change independently.
  let _ = write(context, "/boxes/" <> copy <> "/files/a.txt", "b")
  let response =
    simulate.request(http.Get, "/boxes/" <> home <> "/files/a.txt")
    |> dispatch(context)
  assert "a" == simulate.read_body(response)
  let response =
    simulate.request(http.Get, "/boxes/" <> copy <> "/files/a.txt")
    |> dispatch(context)
  assert "b" == simulate.read_body(response)
}

pub fn concurrent_changes_test() {
  let context = helpers.pool_context()
  let created =
    create(context, [#("name", json.string(helpers.unique("concurrent")))])
  assert 201 == created.status
  let box = id(created)
  let replies = process.new_subject()
  let writes = list.repeat(Nil, 10)
  list.index_map(writes, fn(_, i) {
    process.spawn(fn() {
      let path = "/boxes/" <> box <> "/files/" <> int.to_string(i) <> ".txt"
      process.send(replies, write(context, path, "x").status)
    })
  })
  // No change is lost because another was made at the same time.
  list.each(writes, fn(_) {
    assert Ok(200) == process.receive(replies, 5000)
  })
  let response = dispatch(simulate.request(http.Get, "/boxes/" <> box), context)
  assert 11 == field(response, "sequence", decode.int)
}

pub fn box_secrets_test() {
  use context <- helpers.context()
  let home = "/boxes/" <> id(create(context, [#("name", json.string("home"))]))
  let set = fn(name, value) {
    simulate.request(http.Put, home <> "/secrets/" <> name)
    |> simulate.string_body(value)
    |> dispatch(context)
  }
  assert 204 == set("TOKEN", "abc").status
  assert 204 == set("A_KEY", "def").status
  assert 422 == set("lower", "x").status
  // Only names are listed.
  let response =
    dispatch(simulate.request(http.Get, home <> "/secrets"), context)
  assert "[\"A_KEY\",\"TOKEN\"]" == simulate.read_body(response)

  let response =
    simulate.request(http.Delete, home <> "/secrets/TOKEN") |> dispatch(context)
  assert 204 == response.status
  let response =
    dispatch(simulate.request(http.Get, home <> "/secrets"), context)
  assert "[\"A_KEY\"]" == simulate.read_body(response)
}
