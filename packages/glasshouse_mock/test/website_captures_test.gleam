import glasshouse/archive
import glasshouse/bundle
import glasshouse/data
import glasshouse/store
import gleam/list
import gleam/option.{Some}
import gleam/result
import loam/environment
import simplifile

pub fn website_sealed_captures_open_under_the_current_runtime_test() {
  list.each(
    [
      "sandbox",
      "sandbox-same",
      "sandbox-totals",
      "sandbox-blog",
      "sandbox-stopped",
    ],
    fn(slug) {
      let assert Ok(text) =
        simplifile.read(
          "../website/src/website/routes/glasshouse/demo/" <> slug <> ".json",
        )
      let assert Ok(archive) = archive.from_string(text)
      assert archive.missing(archive) == []
      let assert Some(root) = archive.sandbox
      let assert Ok(descriptor) = store.get_node(archive.store, root)
      list.each(["input", "output"], fn(field) {
        let assert Ok(node) = data.field(descriptor, field)
        let assert Ok(id) = data.reference(node)
        let loaded = environment.open(bundle.new(id, archive.store))
        assert result.is_ok(loaded)
          as { slug <> " " <> field <> " needs a fresh capture" }
      })
    },
  )
}
