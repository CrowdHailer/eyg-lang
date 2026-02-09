import eyg/interpreter/value
import eyg/ir/cid
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/option.{Some}
import morph/analysis
import morph/editable
import morph/picker
import multiformats/cid/v1
import website/components/shell
import website/components/snippet
import website/helpers.{cid_from_tree} as _
import website/routes/editor
import website/routes/helpers
import website/sync/client
import website/sync/protocol
import website/sync/protocol/server

pub fn initial_package_sync_test() {
  let #(state, actions) = editor.init(helpers.config())
  assert client.syncing(state.sync) == True
  let assert [editor.SyncAction(client.SyncFrom(since: 0, ..))] = actions

  let source = ir.integer(100)
  let cid1 = cid_from_tree(source)
  let p1 = protocol.ReleasePublished("foo", 1, cid1)
  let response = server.pull_events_response([p1], 1)

  let message = editor.SyncMessage(client.ReleasesFetched(Ok(response)))
  let #(state, actions) = editor.update(state, message)
  assert client.syncing(state.sync) == True
  let assert [editor.SyncAction(client.FetchFragments(cids:, ..))] = actions
  assert cids == [cid1]

  let response = server.fetch_fragment_response(source)
  let message = editor.SyncMessage(client.FragmentFetched(cid1, Ok(response)))
  let #(state, actions) = editor.update(state, message)
  assert actions == []

  let message =
    editor.ShellMessage(
      shell.CurrentMessage(snippet.UserPressedCommandKey("@")),
    )
  let #(state, actions) = editor.update(state, message)
  assert actions == [editor.FocusOnInput]
  let assert snippet.Editing(mode) = state.shell.source.status

  let assert snippet.SelectRelease(autocomplete:, ..) = mode
  let assert [analysis.Release(package: "foo", version: 1, ..)] =
    autocomplete.items
  // TODO test type and run
}

// test network error fetching packages
// fetch fragment from source
// read the file

pub fn run_anonymous_reference_test() {
  let state = no_packages()
  let message =
    editor.ShellMessage(
      shell.CurrentMessage(snippet.UserPressedCommandKey("#")),
    )
  let #(state, actions) = editor.update(state, message)
  assert actions == [editor.FocusOnInput]
  let assert snippet.Editing(mode) = state.shell.source.status
  let assert snippet.Pick(picker.Typing(..), ..) = mode

  let source = ir.unit()
  let cid = cid_from_tree(source)

  let message =
    editor.ShellMessage(
      shell.CurrentMessage(
        snippet.MessageFromPicker(picker.Decided(v1.to_string(cid))),
      ),
    )
  let #(state, actions) = editor.update(state, message)
  let assert snippet.Editing(snippet.Command) = state.shell.source.status
  let assert [editor.FocusOnBuffer, editor.SyncAction(action)] = actions
  let assert client.FetchFragments(cids:, ..) = action
  assert cids == [cid]
  // At this point is the snippet fetching what's it's type
}

// Reading from scratch is not the same as referencing scratch which must also work
pub fn read_from_scratch_test() {
  let state = no_packages()
  let source = ir.call(ir.perform("ReadFile"), [ir.string("index.eyg.json")])
  let source = editable.from_annotated(source)
  let message = editor.ShellMessage(shell.ParentSetSource(source))
  let #(state, actions) = editor.update(state, message)
  assert actions == [editor.FocusOnBuffer]
  let message =
    editor.ShellMessage(
      shell.CurrentMessage(snippet.UserPressedCommandKey("Enter")),
    )

  let #(state, actions) = editor.update(state, message)
  // The ReadFile effect is synchronous in the editor so it concludes.
  assert actions == [editor.FocusOnBuffer]

  let bytes = dag_json.to_block(ir.vacant())
  let assert [shell.Executed(value:, effects:, ..)] = state.shell.previous
  let lowered = value.ok(value.Binary(bytes))
  assert value == Some(lowered)
  assert effects == [#("ReadFile", #(value.String("index.eyg.json"), lowered))]
}

fn no_packages() {
  let #(state, actions) = editor.init(helpers.config())
  let assert [editor.SyncAction(client.SyncFrom(since: 0, ..))] = actions
  let response = server.pull_events_response([], 0)
  let message = editor.SyncMessage(client.ReleasesFetched(Ok(response)))
  let #(state, actions) = editor.update(state, message)
  assert actions == []
  state
}
