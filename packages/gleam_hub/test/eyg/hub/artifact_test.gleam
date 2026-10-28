import eyg/hub/artifact
import eyg/hub/schema.{ArtifactFile}
import gleam/int
import gleam/list
import gleam/string

fn html(content) {
  ArtifactFile("index.html", "text/html", <<content:utf8>>)
}

pub fn valid_bundle_test() {
  assert Ok(Nil)
    == artifact.validate("board", [
      html("<h1>Hi</h1>"),
      ArtifactFile("assets/style.css", "text/css", <<"h1 {}">>),
      ArtifactFile("logo.png", "image/png", <<137, 80, 78, 71>>),
    ])
}

pub fn name_test() {
  assert Error("Artifact name must contain 1–120 characters")
    == artifact.validate(" ", [html("")])
  assert Ok(Nil) == artifact.validate(string.repeat("a", 120), [html("")])
  assert Error("Artifact name must contain 1–120 characters")
    == artifact.validate(string.repeat("a", 121), [html("")])
}

pub fn index_test() {
  assert Error("Bundle requires index.html with media_type text/html")
    == artifact.validate("a", [])
  assert Error("Bundle requires index.html with media_type text/html")
    == artifact.validate("a", [ArtifactFile("index.html", "text/plain", <<>>)])
  assert Error("index.html must be UTF-8")
    == artifact.validate("a", [ArtifactFile("index.html", "text/html", <<255>>)])
}

pub fn size_test() {
  let files =
    int.range(from: 0, to: artifact.max_files, with: [], run: fn(files, i) {
      [ArtifactFile(int.to_string(i) <> ".txt", "text/plain", <<>>), ..files]
    })
  assert Ok(Nil) == artifact.validate("a", [html(""), ..list.drop(files, 1)])
  assert Error("A bundle may contain at most 128 files and 2 MiB")
    == artifact.validate("a", [html(""), ..files])

  let mebibyte = string.repeat("a", 1_048_576)
  let a = ArtifactFile("a.txt", "text/plain", <<mebibyte:utf8>>)
  let b = ArtifactFile("b.txt", "text/plain", <<mebibyte:utf8>>)
  assert Ok(Nil) == artifact.validate("a", [html(""), a, b])
  assert Error("A bundle may contain at most 128 files and 2 MiB")
    == artifact.validate("a", [html("x"), a, b])
}

pub fn duplicate_path_test() {
  assert Error("Invalid or duplicate bundle path: index.html")
    == artifact.validate("a", [html(""), html("")])
}

pub fn paths_test() {
  assert artifact.valid_path("index.html")
  assert artifact.valid_path("assets/fonts/inter.woff2")
  assert artifact.valid_path("a b.txt")
  assert !artifact.valid_path("")
  assert !artifact.valid_path("/index.html")
  assert !artifact.valid_path("assets/")
  assert !artifact.valid_path("a//b")
  assert !artifact.valid_path("./a")
  assert !artifact.valid_path("../secret")
  assert !artifact.valid_path("a\\b")
  assert !artifact.valid_path("https://example.com")
  assert !artifact.valid_path("a?b")
  assert !artifact.valid_path("a#b")
  assert !artifact.valid_path("%2e%2e")
  assert !artifact.valid_path("a\u{0000}")
  assert Error("Invalid or duplicate bundle path: ../secret")
    == artifact.validate("a", [
      html(""),
      ArtifactFile("../secret", "text/plain", <<>>),
    ])
}

pub fn media_types_test() {
  assert artifact.valid_media_type("text/html")
  assert artifact.valid_media_type("image/svg+xml")
  assert artifact.valid_media_type("application/vnd.api+json")
  assert !artifact.valid_media_type("text")
  assert !artifact.valid_media_type("text/")
  assert !artifact.valid_media_type("text/html/x")
  assert !artifact.valid_media_type("text/html;charset=utf-8")
  assert !artifact.valid_media_type("text/html\r\nx-injected: 1")
  assert !artifact.valid_media_type("text/html ")
  assert Error("Invalid media type: text/html;charset=utf-8")
    == artifact.validate("a", [
      html(""),
      ArtifactFile("b.html", "text/html;charset=utf-8", <<>>),
    ])
}

pub fn ids_test() {
  assert artifact.valid_id("0b5e3f0c-58a1-4c1e-9a53-2f0f5a8c9d11")
  assert !artifact.valid_id("0B5E3F0C-58A1-4C1E-9A53-2F0F5A8C9D11")
  assert !artifact.valid_id("0b5e3f0c58a14c1e9a532f0f5a8c9d11")
  assert !artifact.valid_id("0b5e3f0c-58a1-4c1e-9a53-2f0f5a8c9d1")
  assert !artifact.valid_id("0b5e3f0c-58a1-4c1e-9a53-2f0f5a8c9d11a")
  assert !artifact.valid_id("../../0b5e3f0c-58a1-4c1e-9a53-2f0f5a8")
  assert !artifact.valid_id("")
}
