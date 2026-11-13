import gleam/option.{Some}
import html_parser
import overlay/web/artifact/html

fn unchanged(source) {
  html.rewrite(source, fn(element) { Ok(Some(element)) })
}

pub fn text_between_tags_is_kept_test() {
  assert unchanged("<p><b>Note:</b> read\n  <i>this</i> 1 < 2</p>")
    == Ok("<p><b>Note:</b> read\n  <i>this</i> 1 < 2</p>")
}

pub fn script_contents_and_comments_are_kept_test() {
  assert unchanged("<!-- <img src=x> --><script>if (a<b) {}</script>")
    == Ok("<!-- <img src=x> --><script>if (a<b) {}</script>")
}

pub fn doctype_is_removed_test() {
  assert unchanged("<!DOCTYPE html>\n<html lang=en>")
    == Ok("\n<html lang=\"en\">")
}

pub fn self_closing_tags_are_closed_test() {
  assert unchanged("<svg><path d='M0 0'/><br/></svg>")
    == Ok("<svg><path d=\"M0 0\"></path><br></svg>")
}

pub fn attribute_values_are_escaped_test() {
  let assert Ok(output) =
    html.rewrite("<a title='say \"hi\"' href=x>", fn(element) {
      Ok(Some(html.set_attribute(element, "href", "\"><script>")))
    })
  assert output == "<a title=\"say &quot;hi&quot;\" href=\"&quot;><script>\">"
}

pub fn update_errors_stop_the_rewrite_test() {
  assert html.rewrite("<p><img>", fn(element) {
      case element {
        html_parser.StartElement("img", ..) -> Error("no images")
        _ -> Ok(Some(element))
      }
    })
    == Error("no images")
}
