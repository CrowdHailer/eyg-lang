import cloud/artifacts
import cloud/server
import gleam/option.{None, Some}
import howdy/testing

const general = artifacts.Channel("chat:C1", "general")

const notes = artifacts.Channel("chat:C2", "notes")

fn page(text) {
  [artifacts.File("index.html", "text/html", <<text:utf8>>)]
}

fn store() {
  let assert Ok(store) = artifacts.start("http://cloud.test")
  store
}

fn save(store, name, bundle, by) {
  artifacts.call(store, artifacts.Save(name, bundle, by, _))
}

pub fn versions_test() {
  let store = store()
  assert save(store, "notebook", page("one"), general)
    == Ok(artifacts.Saved(1, "http://cloud.test/artifacts/notebook/"))
  let assert Ok(artifacts.Saved(2, _)) =
    save(store, "notebook", page("two"), general)
  assert artifacts.call(store, artifacts.Get("notebook", None, _))
    == Ok(#(2, page("two")))
  assert artifacts.call(store, artifacts.Get("notebook", Some(1), _))
    == Ok(#(1, page("one")))
}

pub fn only_the_owner_updates_until_shared_test() {
  let store = store()
  let assert Ok(_) = save(store, "notebook", page("one"), general)
  assert save(store, "notebook", page("mine"), notes)
    == Error(
      "Artifact notebook belongs to #general, only that channel can change it unless it is shared",
    )
  let assert Error(_) =
    artifacts.call(store, artifacts.Share("notebook", notes, _))
  let assert Ok(_) =
    artifacts.call(store, artifacts.Share("notebook", general, _))
  let assert Ok(artifacts.Saved(2, _)) =
    save(store, "notebook", page("ours"), notes)
}

pub fn bundle_rules_test() {
  let assert Error(_) = artifacts.validate("x", [])
  let assert Error(_) =
    artifacts.validate("x", [
      artifacts.File("index.html", "text/html", <<"a":utf8>>),
      artifacts.File("../secret", "text/plain", <<>>),
    ])
  let assert Error(_) =
    artifacts.validate("x", [artifacts.File("index.html", "text html", <<>>)])
  let assert Error(_) = artifacts.validate("", page("a"))
  let assert Ok(Nil) =
    artifacts.validate("x", [
      artifacts.File("index.html", "text/html", <<"a":utf8>>),
      artifacts.File("app/main.js", "text/javascript", <<"b":utf8>>),
    ])
}

pub fn serve_test() {
  let store = store()
  let assert Ok(_) = save(store, "my notes", page("one"), general)
  let assert Ok(_) = save(store, "my notes", page("two"), general)
  let get = fn(path) {
    let response = testing.get(path) |> testing.send(server.app(store))
    #(response.status, testing.text(response))
  }
  let #(status, _) = get("/artifacts/my%20notes/")
  assert status == 200
  let #(_, body) = get("/artifacts/my%20notes/v/1/index.html")
  assert body == "one"
  let #(status, _) = get("/artifacts/missing/")
  assert status == 404
}
