import eyg/ir/tree as ir
import gleam/string
import lustre/element
import morph/editable as e
import morph/lustre
import morph/lustre/render

fn html(exp) {
  render.expression(exp, [], [])
  |> lustre.frame
  |> element.to_string
}

pub fn query_operations_render_as_keywords_test() {
  let match = html(e.Query(ir.Match("Edge", ["from", "to"])))
  assert string.contains(match, "class=\"token keyword\"")
  assert string.contains(match, ">match </span>")
  assert string.contains(match, ">Edge{from, to}</span>")
  assert string.contains(html(e.Query(ir.Fact("Edge"))), ">fact </span>")
  assert string.contains(html(e.Query(ir.Resolve("Out"))), ">resolve </span>")
}
