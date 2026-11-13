import eyg/hub/client
import eyg/hub/schema.{ArtifactFile}
import gleam/bit_array
import gleam/crypto
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import hub/artifacts/data
import hub/helpers.{dispatch}
import hub/router
import ogre/operation
import pog
import wisp/simulate

fn html(text) {
  ArtifactFile("index.html", "text/html", bit_array.from_string(text))
}

const svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"/>"

fn bundle() {
  [
    html("<img src=\"images/my pic.svg\">"),
    ArtifactFile("images/my pic.svg", "image/svg+xml", <<svg:utf8>>),
  ]
}

fn share(name, files, context) {
  case share_version(name, files, None, context) {
    Ok(Ok(shared)) -> Ok(Ok(shared.id))
    Ok(Error(reason)) -> Ok(Error(reason))
    Error(failure) -> Error(failure)
  }
}

fn share_version(name, files, previous, context) {
  let response = dispatch(client.share_artifact(name, files, previous), context)
  client.share_artifact_response(response)
}

fn page(id, context) {
  let assert Ok(page) =
    bit_array.to_string(get("/artifact/" <> id, context).body)
  page
}

fn get(path, context) {
  let request = simulate.request(http.Get, path)
  let response = router.route(request, context)
  response.Response(..response, body: simulate.read_body_bits(response))
}

pub fn share_and_fetch_an_artifact_test() {
  use context <- helpers.web_context()
  let assert Ok(Ok(id)) = share("departures", bundle(), context)
  assert 36 == string.length(id)

  let response = dispatch(client.get_artifact(id), context)
  let assert Ok(Ok(#("departures", files))) =
    client.get_artifact_response(response)
  assert list.sort(bundle(), fn(a, b) { string.compare(a.path, b.path) })
    == files
}

pub fn files_are_served_in_a_sandbox_test() {
  use context <- helpers.web_context()
  let assert Ok(Ok(id)) = share("departures", bundle(), context)

  let response = get("/artifacts/" <> id <> "/files/index.html", context)
  assert 200 == response.status
  assert Ok("text/html; charset=utf-8")
    == response.get_header(response, "content-type")
  let assert Ok(policy) =
    response.get_header(response, "content-security-policy")
  assert string.starts_with(policy, "sandbox allow-scripts;")
  assert string.contains(policy, "connect-src 'none'")
  assert Ok("nosniff")
    == response.get_header(response, "x-content-type-options")
  assert <<"<img src=\"images/my pic.svg\">":utf8>> == response.body

  let response =
    get("/artifacts/" <> id <> "/files/images/my%20pic.svg", context)
  assert 200 == response.status
  assert Ok("image/svg+xml") == response.get_header(response, "content-type")
  assert <<svg:utf8>> == response.body

  assert 404 == get("/artifacts/" <> id <> "/files/secret.png", context).status
}

pub fn page_shows_the_artifact_in_a_sandboxed_frame_test() {
  use context <- helpers.web_context()
  let assert Ok(Ok(id)) = share("<b>Buses</b>", bundle(), context)

  let response = get("/artifact/" <> id, context)
  assert 200 == response.status
  let assert Ok(page) = bit_array.to_string(response.body)
  assert string.contains(
    page,
    "src=\"/artifacts/" <> id <> "/files/index.html\" sandbox=\"allow-scripts\"",
  )
  assert string.contains(page, "<h1>&lt;b&gt;Buses&lt;/b&gt;</h1>")
  assert !string.contains(page, "<b>Buses</b>")
  let assert Ok(policy) =
    response.get_header(response, "content-security-policy")
  assert string.contains(policy, "frame-ancestors 'none'")
}

pub fn unknown_artifacts_are_not_found_test() {
  use context <- helpers.web_context()
  assert 404 == get("/artifact/not-an-id", context).status
  assert 404
    == get("/artifact/00000000-0000-0000-0000-000000000000", context).status
  assert 404 == get("/artifacts/'; DROP TABLE artifacts; --", context).status
  assert 404
    == get(
      "/artifacts/00000000-0000-0000-0000-000000000000/files/index.html",
      context,
    ).status
}

pub fn invalid_bundles_are_rejected_test() {
  use context <- helpers.web_context()
  assert Ok(Error("Bundle requires index.html with media_type text/html"))
    == share("a", [ArtifactFile("page.html", "text/html", <<>>)], context)
  assert Ok(Error("index.html must be UTF-8"))
    == share("a", [ArtifactFile("index.html", "text/html", <<255>>)], context)
  assert Ok(Error("Invalid or duplicate bundle path: ../secret"))
    == share(
      "a",
      [html(""), ArtifactFile("../secret", "text/plain", <<>>)],
      context,
    )
  assert Ok(Error("Invalid or duplicate bundle path: index.html"))
    == share("a", [html(""), html("")], context)
  assert Ok(Error("Invalid media type: text/html;charset=utf-8"))
    == share(
      "a",
      [html(""), ArtifactFile("b.html", "text/html;charset=utf-8", <<>>)],
      context,
    )
  assert Ok(Error("Artifact name must contain 1–120 characters"))
    == share(" ", [html("")], context)

  let request =
    operation.post("/artifacts")
    |> operation.set_header("content-type", "application/json")
    |> operation.set_body(<<"{\"name\": 1}">>)
  assert 400 == dispatch(request, context).status
}

pub fn sharing_is_rate_limited_by_address_test() {
  use context <- helpers.web_context()
  let ip = helpers.test_ip()
  let request =
    simulate.request(http.Post, "/artifacts")
    |> simulate.string_body(
      "{\"name\":\"a\",\"files\":[{\"path\":\"index.html\",\"media_type\":\"text/html\",\"content\":\"\"}]}",
    )
    |> request.set_header("content-type", "application/json")
    |> request.set_header("x-forwarded-for", ip)
  list.repeat(Nil, 30)
  |> list.each(fn(_) {
    assert 201 == router.route(request, context).status
  })
  assert 429 == router.route(request, context).status
}

pub fn withdrawn_artifacts_are_not_found_test() {
  use context <- helpers.web_context()
  let assert Ok(Ok(id)) = share("departures", bundle(), context)
  let assert Ok(pog.Returned(rows: [withdrawn], ..)) =
    pog.execute(data.withdraw(id), context.db)
  assert id == withdrawn

  assert 404 == get("/artifact/" <> id, context).status
  assert 404 == get("/artifacts/" <> id, context).status
  assert 404 == get("/artifacts/" <> id <> "/files/index.html", context).status
  let assert Ok(pog.Returned(rows: [], ..)) =
    pog.execute(data.withdraw(id), context.db)
}

pub fn a_newer_version_is_linked_from_the_previous_version_test() {
  use context <- helpers.web_context()
  let assert Ok(Ok(first)) = share_version("board", bundle(), None, context)
  let assert Ok(Ok(second)) =
    share_version("board", bundle(), Some(first), context)
  assert first.secret != second.secret

  let link = "href=\"/artifact/" <> second.id <> "\""
  assert string.contains(page(first.id, context), "<link rel=\"next\" " <> link)
  assert string.contains(page(first.id, context), link <> ">newer version</a>")
  assert !string.contains(page(second.id, context), "newer version")

  // A withdrawn version is not linked.
  let assert Ok(pog.Returned(rows: [_], ..)) =
    pog.execute(data.withdraw(second.id), context.db)
  assert !string.contains(page(first.id, context), "newer version")
}

pub fn a_newer_version_needs_the_secret_of_the_previous_version_test() {
  use context <- helpers.web_context()
  let assert Ok(Ok(first)) = share_version("board", bundle(), None, context)
  let rejected =
    Ok(Error("The previous version is not shared with this secret"))

  let guessed = schema.SharedArtifact(..first, secret: "guess")
  assert rejected == share_version("board", bundle(), Some(guessed), context)
  let unknown =
    schema.SharedArtifact(
      id: "00000000-0000-0000-0000-000000000000",
      secret: first.secret,
    )
  assert rejected == share_version("board", bundle(), Some(unknown), context)
  let invalid = schema.SharedArtifact(id: "not-an-id", secret: first.secret)
  assert rejected == share_version("board", bundle(), Some(invalid), context)
  assert !string.contains(page(first.id, context), "newer version")

  // Only a hash of the secret is stored.
  let assert Ok(pog.Returned(rows: [], ..)) =
    pog.execute(data.shared_with(first.id, <<first.secret:utf8>>), context.db)
  let hash = crypto.hash(crypto.Sha256, <<first.secret:utf8>>)
  let assert Ok(pog.Returned(rows: [_], ..)) =
    pog.execute(data.shared_with(first.id, hash), context.db)
}
