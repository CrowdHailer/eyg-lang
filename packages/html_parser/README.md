> Vendored from [calvinmclean/html_parser](https://github.com/calvinmclean/html_parser) at 30409fb.
> Fixes made here are offered upstream, depend on the released package once they are published.

# html_parser

[![Package Version](https://img.shields.io/hexpm/v/html_parser)](https://hex.pm/packages/html_parser)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/html_parser/)

`html_parser` is a simple library for parsing an HTML document. Use `html_parser.as_list` to parse the document
as List of Elements. Use `html_parser.as_tree` to create a nested structure where Elements have children.

- `StartElement`: HTML opening tag, like `<div>`
- `EndElement`: HTML closing tag, like `</div>`
- `Content`: Non-HTML parts of the document inside tags (the "hello" in `<div>hello</div>`)
- `Attributes`: HTML attributes inside of a tag (`href` key and value in `<a href="github.com">`)

```sh
gleam add html_parser@1
```
```gleam
import html_parser

pub fn main() {
  "<div><div class=\"data\">Data!</div></div>"
  |> html_parser.as_list
  |> find_div
  |> io.debug
}

// find a starting div where class=data and the next element is Content
fn find_div(in: List(html_parser.Element)) -> String {
  case in {
    [] -> "Not found"
    [
      html_parser.StartElement("div", [html_parser.Attribute("class", "data")], _),
      html_parser.Content(contents),
      ..
    ] -> contents
    [_, ..tail] -> find_div(tail)
  }
}
```

Further documentation can be found at <https://hexdocs.pm/html_parser>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```
