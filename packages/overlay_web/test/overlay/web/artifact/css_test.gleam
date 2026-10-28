import overlay/web/artifact/css

fn rewrite(source) {
  css.rewrite(source, fn(reference) {
    case reference {
      css.Url(location) -> Ok("u:" <> location)
      css.Import(location) -> Ok("i:" <> location)
    }
  })
}

pub fn no_references_are_unchanged_test() {
  let source = "body { color: red; margin: 0 }\n.a::after { content: 'é' }"
  assert rewrite(source) == Ok(source)
}

pub fn url_forms_test() {
  assert rewrite("a{background:url(x.png)}")
    == Ok("a{background:url(\"u:x.png\")}")
  assert rewrite("a{background:url( 'x.png' )}")
    == Ok("a{background:url(\"u:x.png\")}")
  assert rewrite("a{background:URL(\"x y.png\")}")
    == Ok("a{background:url(\"u:x y.png\")}")
  assert rewrite("a{background:url(  x.png  )}")
    == Ok("a{background:url(\"u:x.png\")}")
  assert rewrite("a{b:url(1.png),url(2.png)}")
    == Ok("a{b:url(\"u:1.png\"),url(\"u:2.png\")}")
}

pub fn comments_and_strings_are_not_references_test() {
  let source = "/* url(a.png) */ a::after{content:\"url(b.png)\"}"
  assert rewrite(source) == Ok(source)
  assert rewrite("/* unterminated url(a.png)")
    == Ok("/* unterminated url(a.png)")
}

pub fn url_must_start_a_function_name_test() {
  let source = "a{b:myurl(x.png);c:my-url(y)}"
  assert rewrite(source) == Ok(source)
}

pub fn import_forms_test() {
  assert rewrite("@import \"a.css\";") == Ok("@import \"i:a.css\";")
  assert rewrite("@import 'a.css' screen;") == Ok("@import \"i:a.css\" screen;")
  assert rewrite("@IMPORT url(a.css);") == Ok("@IMPORT \"i:a.css\";")
  assert rewrite("@import/**/\"a.css\";") == Ok("@import/**/\"i:a.css\";")
  assert rewrite("@imports \"a.css\";") == Ok("@imports \"a.css\";")
}

pub fn escapes_are_decoded_and_replacements_quoted_test() {
  let assert Ok(output) =
    css.rewrite("a{b:url(\"q\\\"\\31 23\\\nx\")}", fn(reference) {
      let assert css.Url(location) = reference
      Ok(location)
    })
  assert output == "a{b:url(\"q\\\"123x\")}"
  let assert Ok(output) =
    css.rewrite("a{b:url(p\\)q.png)}", fn(reference) {
      let assert css.Url(location) = reference
      Ok(location <> "\\")
    })
  assert output == "a{b:url(\"p)q.png\\\\\")}"
}

pub fn unclosed_url_keeps_remaining_source_test() {
  assert rewrite("a{b:url(x.png)} c{d:url(y.png")
    == Ok("a{b:url(\"u:x.png\")} c{d:url(y.png")
}

pub fn replace_errors_are_returned_test() {
  assert css.rewrite("a{b:url(missing.png)}", fn(_) { Error("missing") })
    == Error("missing")
}

pub fn declarations_test() {
  assert rewrite("background-image: url(image.svg); color: red")
    == Ok("background-image: url(\"u:image.svg\"); color: red")
}
