import gleam/bit_array
import gleam/string
import overlay/web/artifact
import overlay/web/artifact/inline

fn file(path, media_type, text) {
  artifact.File(path, media_type, bit_array.from_string(text))
}

const svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"/>"

fn bundle() {
  [
    file("index.html", "text/html", "<h1>hi</h1>"),
    file(
      "css/main.css",
      "text/css",
      "@import \"nested.css\"; a{b:url(../icon.svg#x)}",
    ),
    file(
      "css/nested.css",
      "text/css",
      "body{background:url('../images/my pic.svg')}",
    ),
    file("icon.svg", "image/svg+xml", svg),
    file("images/my pic.svg", "image/svg+xml", svg),
    file("loop/a.css", "text/css", "@import 'b.css';"),
    file("loop/b.css", "text/css", "@import url(a.css);"),
  ]
}

pub fn resolve_relative_to_file_test() {
  let assert Ok(#(found, "")) =
    inline.resolve(bundle(), "icon.svg", "index.html")
  assert found.path == "icon.svg"
  let assert Ok(#(found, "#x")) =
    inline.resolve(bundle(), "../icon.svg#x", "css/main.css")
  assert found.path == "icon.svg"
  let assert Ok(#(found, "")) =
    inline.resolve(bundle(), "/images/my%20pic.svg", "css/main.css")
  assert found.path == "images/my pic.svg"
  let assert Ok(#(found, "")) =
    inline.resolve(bundle(), "./nested.css?version=2", "css/main.css")
  assert found.path == "css/nested.css"
}

pub fn resolve_rejects_missing_and_external_test() {
  assert inline.resolve(bundle(), "secret.png", "index.html")
    == Error("Missing bundle file: secret.png")
  assert inline.resolve(bundle(), "../../../icon.svg", "css/main.css")
    |> is_ok
  assert inline.resolve(bundle(), "https://example.com/x.png", "index.html")
    == Error("External resource must be bundled: https://example.com/x.png")
  assert inline.resolve(bundle(), "//example.com/x.png", "index.html")
    == Error("External resource must be bundled: //example.com/x.png")
  assert inline.resolve(bundle(), "javascript:alert(1)", "index.html")
    == Error("External resource must be bundled: javascript:alert(1)")
  assert inline.resolve(
      bundle(),
      "https://bundle.invalid:8080/icon.svg",
      "index.html",
    )
    == Error(
      "External resource must be bundled: https://bundle.invalid:8080/icon.svg",
    )
}

fn is_ok(result) {
  case result {
    Ok(_) -> True
    Error(_) -> False
  }
}

pub fn asset_keeps_data_urls_and_fragments_test() {
  assert inline.asset(bundle(), "data:image/png;base64,AA==", "index.html")
    == Ok("data:image/png;base64,AA==")
  assert inline.asset(bundle(), "#section", "index.html") == Ok("#section")
  let assert Ok(url) = inline.asset(bundle(), "icon.svg#x", "index.html")
  assert url
    == "data:image/svg+xml;base64,"
    <> bit_array.base64_encode(bit_array.from_string(svg), True)
    <> "#x"
}

pub fn data_url_requires_plain_media_type_test() {
  assert inline.data_url(file("x", "text/html;charset=utf-8", ""))
    == Error("Invalid media type for x")
  assert inline.data_url(file("x", "text/html,<script>", ""))
    == Error("Invalid media type for x")
}

pub fn stylesheet_inlines_nested_imports_and_assets_test() {
  let assert Ok(file) = artifact.file(bundle(), "css/main.css")
  let assert Ok(source) = inline.text(file)
  let assert Ok(output) = inline.stylesheet(bundle(), source, file.path)
  let assert "@import \"data:text/css;charset=utf-8;base64," <> rest = output
  let assert Ok(#(encoded, rest)) = string.split_once(rest, "\"")
  let assert Ok(nested) = bit_array.base64_decode(encoded)
  let assert Ok(nested) = bit_array.to_string(nested)
  assert string.starts_with(nested, "body{background:url(\"data:image/svg+xml;")
  assert string.starts_with(rest, "; a{b:url(\"data:image/svg+xml;base64,")
  assert string.ends_with(rest, "#x\")}")
}

pub fn circular_imports_are_rejected_test() {
  assert inline.stylesheet(bundle(), "@import 'loop/a.css';", "index.html")
    == Error("Circular CSS import: loop/a.css")
}

pub fn document_inlines_references_test() {
  let assert Ok(output) =
    inline.document(
      bundle(),
      "<!doctype html><base href=\"https://example.com/\"><link rel=icon href=x.ico><link rel=\"stylesheet\" href=\"css/nested.css\"><style>p{background:url(icon.svg)}</style><img src=\"icon.svg\" integrity=\"sha-x\" style=\"background:url(icon.svg)\">",
      "index.html",
    )
  let assert "<link rel=\"stylesheet\" href=\"data:text/css;" <> rest = output
  let assert Ok(#(_, rest)) = string.split_once(rest, "\">")
  let assert "<style>p{background:url(\"data:image/svg+xml;" <> rest = rest
  let assert Ok(#(_, rest)) = string.split_once(rest, "</style>")
  let assert "<img src=\"data:image/svg+xml;" <> rest = rest
  assert !string.contains(rest, "integrity")
  assert string.contains(
    rest,
    "style=\"background:url(&quot;data:image/svg+xml;",
  )
}

pub fn document_rejects_srcset_and_missing_files_test() {
  assert inline.document(bundle(), "<img srcset=\"a.png 2x\">", "index.html")
    == Error("Use a bundled src instead of srcset")
  assert inline.document(bundle(), "<img src=\"secret.png\">", "index.html")
    == Error("Missing bundle file: secret.png")
}
