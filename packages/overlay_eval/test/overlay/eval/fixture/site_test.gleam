import gleam/bit_array
import gleam/list
import gleam/string
import ogre/operation
import ogre/origin
import overlay/eval/fixture/site

fn get(site, path) {
  let request =
    operation.get(path) |> operation.to_request(origin.https("eyg.test"))
  let assert Ok(response) = site.handle(site, request)
  let assert Ok(body) = bit_array.to_string(response.body)
  #(response.status, body)
}

pub fn guides_are_served_by_slug_test() {
  let assert Ok(site) = site.load("test/fixtures/guides")
  assert ["files", "eyg-syntax-guide"]
    == list.map(site.guides, fn(guide) { guide.slug })
  let #(status, body) = get(site, "/guides/eyg-syntax-guide.md")
  assert 200 == status
  assert "# EYG Syntax Guide\n\nEverything is an expression.\n" == body
  assert #(200, "Use ReadFile.\n") == get(site, "/guides/files")
  assert 404 == get(site, "/guides/draft.md").0
}

pub fn llms_lists_every_guide_test() {
  let assert Ok(site) = site.load("test/fixtures/guides")
  let #(status, body) = get(site, "/llms.txt")
  assert 200 == status
  assert string.contains(
    body,
    "- [EYG syntax guide](/guides/eyg-syntax-guide.md): Syntax reference for the EYG text representation.",
  )
  assert string.contains(
    body,
    "- [Modifying text_files](/guides/files.md): Read and write",
  )
}

pub fn other_paths_are_not_for_the_site_test() {
  let assert Ok(site) = site.load("test/fixtures/guides")
  let request =
    operation.get("/modules/abc")
    |> operation.to_request(origin.https("eyg.test"))
  assert Error(Nil) == site.handle(site, request)
}
