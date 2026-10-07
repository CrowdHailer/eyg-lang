import gleam/list
import gleam/string
import lustre/element
import pamphlet
import pamphlet/lustre
import website/guide_highlight
import website/routes/guides

pub fn render_route_test() {
  guides.route()
}

pub fn authorization_chapters_render_with_highlighted_examples_test() {
  let assert Ok(guide) =
    list.find(guides.from_repo(), fn(g) { g.slug == "authorization" })
  let html =
    lustre.to_lustre(guide.document, guide_highlight.renderer())(fn(x) { x })
    |> element.to_string
  assert string.contains(html, "Authorization with query literals")
  assert string.contains(
    html,
    "Companies, teams, agents, and long-running tasks",
  )
  assert list.length(string.split(html, "class=\"language-eyg\"")) == 10
  assert string.contains(html, "class=\"table-scroll\"")
  assert !string.contains(html, "```eyg")
}

pub fn query_keywords_are_highlighted_as_keywords_test() {
  let #(_, document) =
    pamphlet.parse(
      "```eyg\nlet db = @{ fact Item(1), rule Out(x) { var x Item(x) } }\nresolve Out db\n```",
    )
  let html =
    lustre.to_lustre(document, guide_highlight.renderer())(fn(x) { x })
    |> element.to_string
  list.each(["fact", "rule", "var", "resolve"], fn(keyword) {
    assert string.contains(html, "color:#F97583;\">" <> keyword <> "</span>")
  })
}

pub fn repository_links_have_published_destinations_test() {
  let known = guides.from_repo()
  assert guides.link_target("./install_from_source.md", known)
    == "/guides/install-from-source"
  assert guides.link_target("syntax.md#query-literals", known)
    == "/guides/eyg-syntax-guide#query-literals"
  assert guides.link_target("../eyg_packages/authorization/", known)
    == "https://github.com/CrowdHailer/eyg-lang/tree/main/eyg_packages/authorization/"
  assert guides.link_target("../examples/authorization/overlay.eyg", known)
    == "https://github.com/CrowdHailer/eyg-lang/blob/main/examples/authorization/overlay.eyg"
  assert guides.link_target("https://example.com/", known)
    == "https://example.com/"
  assert guides.link_target("#the-trust-boundary", known)
    == "#the-trust-boundary"
}
