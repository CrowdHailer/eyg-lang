import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should
import html_parser
import simplifile.{read}

pub fn main() {
  gleeunit.main()
}

fn find_div_tree(in: html_parser.Element) -> Option(html_parser.Element) {
  case in {
    html_parser.StartElement(
      "div",
      [html_parser.Attribute("class", "definition")],
      _,
    ) -> Some(in)
    html_parser.StartElement(_, _, children) -> {
      let subs = list.map(children, find_div_tree)
      case list.find(subs, option.is_some) {
        Ok(res) -> {
          res
        }
        Error(_) -> None
      }
    }
    _ -> None
  }
}

fn find_div_list(in: List(html_parser.Element)) -> html_parser.Element {
  case in {
    [] -> html_parser.EmptyElement
    [
      html_parser.StartElement(
        "div",
        [html_parser.Attribute("class", "definition")],
        _,
      ) as result,
      ..
    ] -> result
    [_, ..tail] -> find_div_list(tail)
  }
}

pub fn parse_aloha_list_test() {
  let assert Ok(input) = read(from: "test/aloha.html")
  input
  |> html_parser.as_list
  |> find_div_list
  |> should.equal(
    html_parser.StartElement(
      "div",
      [html_parser.Attribute("class", "definition")],
      [],
    ),
  )
}

pub fn parse_aloha_tree_test() {
  let assert Ok(input) = read(from: "test/aloha.html")

  let assert Some(div) =
    input
    |> html_parser.as_tree
    |> find_div_tree

  let assert html_parser.StartElement(name, attrs, _) = div

  should.equal(name, "div")
  should.equal(attrs, [html_parser.Attribute("class", "definition")])
}

pub fn get_first_element_test() {
  let tests = [
    #("empty string", "", #(html_parser.EmptyElement, "")),
    #("with content", "hello<div>", #(html_parser.Content("hello"), "<div>")),
    #(
      "with content and spaces",
      "hello  <div>",
      #(html_parser.Content("hello  "), "<div>"),
    ),
    #(
      "with content and end tag",
      "hello</div>",
      #(html_parser.Content("hello"), "</div>"),
    ),
    #(
      "with angle brackets in content",
      "1 < 2 > 0<div>",
      #(html_parser.Content("1 < 2 > 0"), "<div>"),
    ),
    #("div", "<div>", #(html_parser.StartElement("div", [], []), "")),
    #("end div", "</div>", #(html_parser.EndElement("div"), "")),
    #(
      "end div with leading spaces",
      "     </div>",
      #(html_parser.EndElement("div"), ""),
    ),
    #(
      "div with leading spaces",
      "   <div>",
      #(html_parser.StartElement("div", [], []), ""),
    ),
    #(
      "div with internal spaces",
      "<div \t \n  >",
      #(html_parser.StartElement("div", [], []), ""),
    ),
    #(
      "div with remaining",
      "<div>  <div>",
      #(html_parser.StartElement("div", [], []), "  <div>"),
    ),
    #(
      "div with attribute",
      "<div\n a=\"b\">",
      #(
        html_parser.StartElement("div", [html_parser.Attribute("a", "b")], []),
        "",
      ),
    ),
    #(
      "div with attribute and too many spaces",
      "<div     a=\"b\" >",
      #(
        html_parser.StartElement("div", [html_parser.Attribute("a", "b")], []),
        "",
      ),
    ),
    #(
      "div with multiple attribute",
      "<div a=\"b\" c=\"d\">",
      #(
        html_parser.StartElement(
          "div",
          [html_parser.Attribute("a", "b"), html_parser.Attribute("c", "d")],
          [],
        ),
        "",
      ),
    ),
    #(
      "div with space in attribute",
      "<div a=\"two words\">",
      #(
        html_parser.StartElement(
          "div",
          [html_parser.Attribute("a", "two words")],
          [],
        ),
        "",
      ),
    ),
    #(
      "a with href with query parameter",
      "<a href=\"https://website.com/?lang=en\">",
      #(
        html_parser.StartElement(
          "a",
          [html_parser.Attribute("href", "https://website.com/?lang=en")],
          [],
        ),
        "",
      ),
    ),
    #(
      "self-closing",
      "<br/>",
      #(html_parser.StartElement("br", [], []), "</br>"),
    ),
    #(
      "self-closing with attribute",
      "<path d=\"M0 0\" />rest",
      #(
        html_parser.StartElement(
          "path",
          [html_parser.Attribute("d", "M0 0")],
          [],
        ),
        "</path>rest",
      ),
    ),
    #(
      "script contents",
      "<script>if (a<b) {}</script>",
      #(
        html_parser.StartElement("script", [], [
          html_parser.Content("if (a<b) {}"),
        ]),
        "</script>",
      ),
    ),
    #(
      "style contents",
      "<style>p > a {}</b></STYLE >",
      #(
        html_parser.StartElement("style", [], [
          html_parser.Content("p > a {}</b>"),
        ]),
        "</STYLE >",
      ),
    ),
    #(
      "empty script",
      "<script src=\"a.js\"></script>",
      #(
        html_parser.StartElement(
          "script",
          [html_parser.Attribute("src", "a.js")],
          [],
        ),
        "</script>",
      ),
    ),
  ]

  list.each(tests, fn(testcase) {
    let #(_, in, expected) = testcase
    html_parser.get_first_element(in) |> should.equal(expected)
  })
}

pub fn get_attrs_test() {
  let tests = [
    #("empty string", "", #([], "")),
    #("single simple attr", "a=\"b\"", #([html_parser.Attribute("a", "b")], "")),
    #(
      "surrounding spaces",
      "     a=\"b\"",
      #([html_parser.Attribute("a", "b")], ""),
    ),
    #(
      "single larger attr",
      "aaaaaaa=\"bbbbbb\"",
      #([html_parser.Attribute("aaaaaaa", "bbbbbb")], ""),
    ),
    #(
      "multiple simple attr",
      "a=\"b\" \t c=\"d\" e=\"f\"",
      #(
        [
          html_parser.Attribute("a", "b"),
          html_parser.Attribute("c", "d"),
          html_parser.Attribute("e", "f"),
        ],
        "",
      ),
    ),
    #(
      "multiple larger attr",
      "aaaaaaa=\"bbbbbb\" ccc=\"dddd\"",
      #(
        [
          html_parser.Attribute("aaaaaaa", "bbbbbb"),
          html_parser.Attribute("ccc", "dddd"),
        ],
        "",
      ),
    ),
    #(
      "attributes followed by more document",
      "a=\"b\" c=\"d\" > \n</div>",
      #(
        [html_parser.Attribute("a", "b"), html_parser.Attribute("c", "d")],
        " \n</div>",
      ),
    ),
    #(
      "single quoted attr",
      "a='say \"hi\"'>",
      #([html_parser.Attribute("a", "say \"hi\"")], ""),
    ),
    #(
      "unquoted attr",
      "a=b c=d>",
      #([html_parser.Attribute("a", "b"), html_parser.Attribute("c", "d")], ""),
    ),
    #(
      "attr without a value",
      "disabled a=\"b\">",
      #(
        [html_parser.Attribute("disabled", ""), html_parser.Attribute("a", "b")],
        "",
      ),
    ),
    #(
      "closing bracket in quoted attr",
      "a=\"1 > 0\">rest",
      #([html_parser.Attribute("a", "1 > 0")], "rest"),
    ),
  ]

  list.each(tests, fn(testcase) {
    let #(_, in, expected) = testcase
    html_parser.get_attrs(in) |> should.equal(expected)
  })
}

pub fn as_list_test() {
  let tests = [
    #("empty string", "", []),
    #("single start element", "<div>", [html_parser.StartElement("div", [], [])]),
    #("start and end element", "<div> \n \t </div>", [
      html_parser.StartElement("div", [], []),
      html_parser.EndElement("div"),
    ]),
    #("nested elements", "<div><p></p></div>", [
      html_parser.StartElement("div", [], []),
      html_parser.StartElement("p", [], []),
      html_parser.EndElement("p"),
      html_parser.EndElement("div"),
    ]),
    #("element with contents", "<div>hello</div>", [
      html_parser.StartElement("div", [], []),
      html_parser.Content("hello"),
      html_parser.EndElement("div"),
    ]),
    // #(
  //   "element with contents and children",
  //   "<div>hello<div>hello2</div></div>",
  //   [
  //     html_parser.StartElement("div", [], []),
  //     html_parser.Content("hello"),
  //     html_parser.StartElement("div", [], []),
  //     html_parser.Content("hello2"),
  //     html_parser.EndElement("div"),
  //     html_parser.EndElement("div"),
  //   ],
  // ),
  ]
  list.each(tests, fn(testcase) {
    let #(_name, in, expected) = testcase
    html_parser.as_list(in) |> should.equal(expected)
  })
}

pub fn as_tree_test() {
  html_parser.as_tree(
    "
    <div>
      <a></a>
      <p></p>
      <span></span>

      <div>
        <a></a>
        <p></p>
        <span></span>
      </div>

      <span></span>
    </div>
    ",
  )
  |> should.equal(
    html_parser.StartElement("div", [], [
      html_parser.StartElement("a", [], []),
      html_parser.StartElement("p", [], []),
      html_parser.StartElement("span", [], []),
      html_parser.StartElement("div", [], [
        html_parser.StartElement("a", [], []),
        html_parser.StartElement("p", [], []),
        html_parser.StartElement("span", [], []),
      ]),
      html_parser.StartElement("span", [], []),
    ]),
  )
}
