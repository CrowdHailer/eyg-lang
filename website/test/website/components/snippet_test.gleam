import gleam/io
import morph/editable as e
import website/components/snippet
import website/sync/sync

fn init(exp) {
  snippet.init(exp, [], [], sync.init(sync.test_origin))
}

pub fn add_reference_test() {
  let state = init(e.Vacant)
  snippet.update(state, snippet.ClipboardReadCompleted(Ok("")))
  |> io.debug
  todo as "paste ref"
}
