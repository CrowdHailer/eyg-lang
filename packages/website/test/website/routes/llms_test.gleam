import gleam/list
import gleam/string
import website/routes/guides
import website/routes/llms

pub fn content_includes_all_repo_guides_test() {
  let content = llms.content()

  assert list.all(guides.from_repo(), fn(guide) {
    string.contains(content, "/guides/" <> guide.slug <> ".md")
  })
}
