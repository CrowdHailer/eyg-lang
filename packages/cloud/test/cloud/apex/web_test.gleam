import cloud/apex/access
import cloud/apex/server
import cloud/box
import cloud/file_system
import cloud/helpers
import gleam/http/response
import gleam/option.{Some}
import howdy/testing
import multiformats/cid/v1

pub fn serve_artifacts_test() {
  use context <- helpers.context()
  let assert Ok(home) = box.create(context, Some("home"))
  let assert Ok(home) =
    box.change(context, home.id, fn(root) {
      file_system.write(root, "/index.html", <<"<p>hi</p>">>)
    })
  let app = server.app(context, access.Local)
  let url = "/artifacts/" <> v1.to_string(home.root) <> "/index.html"
  let page = testing.get(url) |> testing.send(app)
  assert 200 == page.status
  assert "<p>hi</p>" == testing.text(page)
  assert Ok("text/html; charset=utf-8")
    == response.get_header(page, "content-type")
  // The page runs in a sandbox with its own origin.
  assert Ok("sandbox allow-scripts")
    == response.get_header(page, "content-security-policy")

  let missing =
    testing.get("/artifacts/" <> v1.to_string(home.root) <> "/missing.html")
    |> testing.send(app)
  assert 404 == missing.status
  assert 404 == testing.send(testing.get("/artifacts/nope/a.html"), app).status
}

pub fn refuse_other_origins_test() {
  use context <- helpers.context()
  let app = server.app(context, access.Local)
  let request = fn(origin) {
    testing.get("/")
    |> testing.header("host", "eyg.example:8787")
    |> testing.header("origin", origin)
    |> testing.send(app)
  }
  assert 200 == request("https://eyg.example:8787").status
  // A page in a sandbox, such as an artifact, has no origin of its own.
  assert 403 == request("null").status
  assert 403 == request("https://other.example").status
}
