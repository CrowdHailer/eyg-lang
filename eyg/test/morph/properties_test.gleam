import eygir/annotated
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import lustre/element
import morph/editable as e
import morph/lustre/render
import morph/projection

const src = e.Block(
  [
    #(
      e.Bind("nest"),
      e.Block(
        [#(e.Bind("a"), e.Integer(1)), #(e.Bind("b"), e.Integer(2))],
        e.Vacant(""),
        True,
      ),
    ), #(e.Destructure([#("foo", "foo")]), e.Binary(<<>>)),
  ],
  e.List(
    [e.String("orange"), e.String("apple"), e.String("carrot")],
    Some(e.Variable("x")),
  ),
  False,
)

pub fn editable_property_test() {
  let #(_, revs) =
    e.to_annotated(src, [])
    |> annotated.strip_annotation
  let revs = list.unique(revs)

  let idle =
    render.top(src)
    |> element.fragment
    |> element.to_readable_string
  // |> has_all(revs)

  list.map(revs, fn(rev) {
    let path = list.reverse(rev)
    let p = projection.focus_at(src, path)
    has_attr(idle, rev)
    render.projection(p, True)
    |> element.to_readable_string
    |> has_all(revs)
  })
}

fn has_all(string, revs) {
  list.map(revs, has_attr(string, _))
}

fn has_attr(string, rev) {
  let a = path_attr(rev)
  case string.contains(string, a) {
    True -> Nil
    False -> panic as { string <> "\n\nmissing: " <> a }
  }
}

fn path_attr(rev) {
  "data-rev=\"" <> string.join(list.map(rev, int.to_string), ",") <> "\""
}
