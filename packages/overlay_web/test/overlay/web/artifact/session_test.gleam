import eyg/hub/schema
import gleam/bit_array
import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/string
import overlay/helpers
import overlay/web/artifact as art
import overlay/web/artifact/session
import overlay/web/state
import pal/system

fn bundle(text) {
  [
    art.File("index.html", "text/html", bit_array.from_string(text)),
    art.File("image.png", "image/png", <<0, 255, 128>>),
  ]
}

fn saved_store() {
  let assert Ok(#(store, _)) = art.save(art.new(), "map", bundle("first"))
  let assert Ok(#(store, _)) = art.save(store, "map", bundle("second"))
  let assert Ok(#(store, _)) = art.save(store, "other", bundle("other"))
  let assert Ok(store) = art.show(store, panel(art.Artifact("map")))
  store
}

fn panel(item) {
  art.Placement(item, art.Point(250, 100), art.Point(500, 900))
}

pub fn revisions_bytes_panels_and_completed_shares_round_trip_test() {
  let store = saved_store()
  let assert Ok(store) = art.show(store, panel(art.Revision("map", 1)))
  let assert Ok(store) = art.show(store, panel(art.History("map")))
  let assert Ok(store) = art.show(store, panel(art.Diff("map", 1, 2)))
  let store = art.share(store, "map", 1, art.Shared("id", "secret"))
  let temporary =
    store
    |> art.share("map", 2, art.Sharing)
    |> art.share("other", 1, art.ShareFailed("offline"))
  assert Ok(store) == session.restore(session.encode(temporary))
  assert Ok(art.new()) == session.restore(session.encode(art.new()))
}

pub fn restore_checks_format_paths_and_panel_references_test() {
  let encoded = session.encode(saved_store())
  let assert Error(_) = session.restore("invalid json")
  let assert Error(_) =
    session.restore(string.replace(encoded, "\"format\":1", "\"format\":2"))
  let assert Error(_) =
    session.restore(string.replace(encoded, "index.html", "../secret"))
  let invalid =
    art.Store(..saved_store(), panels: [panel(art.Revision("map", 3))])
  let assert Error(_) = session.restore(session.encode(invalid))
  let invalid =
    art.Store(..saved_store(), panels: [
      art.Placement(art.Artifact("map"), art.Point(-1, 0), art.Point(100, 100)),
    ])
  let assert Error(_) = session.restore(session.encode(invalid))
  let invalid =
    art.share(saved_store(), "missing", 1, art.Shared("id", "secret"))
  let assert Error(_) = session.restore(session.encode(invalid))
}

pub fn restore_preserves_closed_panels_and_does_not_save_again_test() {
  let store = art.close(saved_store(), art.Artifact("map"))
  let #(next, effects) =
    state.update(
      helpers.init_default(),
      state.ArtifactsLoaded(Ok(Some(session.encode(store)))),
    )
  assert store == next.artifacts
  assert [] == next.artifacts.panels
  assert 2 == list.length(art.history(next.artifacts, "map"))
  assert [] == effects
}

pub fn late_restore_does_not_replace_work_already_created_test() {
  let current = state.State(..helpers.init_default(), artifacts: saved_store())
  let #(next, effects) =
    state.update(
      current,
      state.ArtifactsLoaded(Ok(Some(session.encode(art.new())))),
    )
  assert current == next
  assert [] == effects
}

pub fn saves_once_when_execution_finishes_and_retries_storage_failures_test() {
  let store = saved_store()
  let current =
    state.State(
      ..helpers.init_default(),
      artifacts: store,
      status: state.Executing([]),
    )
  let #(current, effects) =
    state.update(current, state.UserClosedArtifact(art.Artifact("map")))
  assert [] == effects
  assert current.artifacts_dirty
  let #(current, effects) = state.update(current, state.UserClickedStop)
  let assert [
    system.SetSessionStorageItem("overlay.artifacts", encoded, resume),
  ] = artifact_saves(effects)
  assert Ok(current.artifacts) == session.restore(encoded)
  assert session.Saving == current.artifact_storage
  assert !current.artifacts_dirty
  let assert system.Done(message) = resume(Error("quota"))
  let #(current, effects) = state.update(current, message)
  assert session.SaveFailed("quota") == current.artifact_storage
  assert [] == effects
  let old_revision = current.artifact_save_revision
  let #(current, effects) = state.update(current, state.UserRetriedArtifactSave)
  let assert [system.SetSessionStorageItem("overlay.artifacts", _, resume)] =
    effects
  let #(current, _) =
    state.update(current, state.ArtifactsSaved(old_revision, Error("stale")))
  assert session.Saving == current.artifact_storage
  let assert system.Done(message) = resume(Ok(Nil))
  let #(current, effects) = state.update(current, message)
  assert session.Saved == current.artifact_storage
  assert [] == effects
}

pub fn corrupt_storage_leaves_a_usable_empty_workspace_test() {
  let #(current, effects) =
    state.update(
      helpers.init_default(),
      state.ArtifactsLoaded(Ok(Some("broken"))),
    )
  let assert session.RestoreFailed(_) = current.artifact_storage
  assert dict.new() == current.artifacts.versions
  assert [] == effects
}

fn artifact_saves(effects) {
  list.filter(effects, fn(effect) {
    case effect {
      system.SetSessionStorageItem("overlay.artifacts", _, _) -> True
      _ -> False
    }
  })
}

pub fn a_completed_share_is_saved_even_while_the_agent_is_busy_test() {
  let current =
    state.State(
      ..helpers.init_default(),
      artifacts: saved_store(),
      status: state.Executing([]),
    )
  let #(next, effects) =
    state.update(
      current,
      state.ArtifactShared("map", 1, Ok(schema.SharedArtifact("id", "secret"))),
    )
  let assert [system.SetSessionStorageItem("overlay.artifacts", encoded, _)] =
    effects
  let assert Ok(restored) = session.restore(encoded)
  assert Ok(art.Shared("id", "secret"))
    == dict.get(restored.shares, #("map", 1))
  let assert state.Executing([]) = next.status
}

pub fn portable_copies_preserve_content_without_sharing_secrets_test() {
  let public_copy = saved_store()
  let owned =
    art.share(public_copy, "map", 1, art.Shared("id", "private-share-secret"))
  let exported = session.export(owned)
  assert !string.contains(exported, "private-share-secret")
  assert Ok(public_copy) == session.import_copy(exported)
  // Imported snapshots cannot bring ownership secrets into another tab either.
  assert Ok(public_copy) == session.import_copy(session.encode(owned))
  let current = state.State(..helpers.init_default(), artifacts: owned)
  let #(_, actions) = state.update(current, state.UserExportedArtifacts)
  let assert [system.Download(input, _)] = actions
  assert "eyg-artifacts.json" == input.name
  assert Ok(exported) == bit_array.to_string(input.content)
}

pub fn import_keeps_existing_work_even_if_it_started_while_the_file_was_read_test() {
  let current = state.State(..helpers.init_default(), artifacts: saved_store())
  let #(next, actions) =
    state.update(current, state.ArtifactFileRead(Ok(session.encode(art.new()))))
  assert current.artifacts == next.artifacts
  let assert Some(_) = next.artifact_import_error
  assert [] == actions
  let current = state.State(..helpers.init_default(), status: state.Asking([]))
  let #(next, actions) =
    state.update(
      current,
      state.ArtifactFileRead(Ok(session.encode(saved_store()))),
    )
  assert art.new() == next.artifacts
  let assert Some(_) = next.artifact_import_error
  assert [] == actions
}

pub fn importing_into_an_empty_tab_saves_a_validated_copy_test() {
  let #(next, actions) =
    state.update(
      helpers.init_default(),
      state.ArtifactFileRead(Ok(session.encode(saved_store()))),
    )
  assert saved_store() == next.artifacts
  let assert [system.SetSessionStorageItem("overlay.artifacts", _, _)] = actions
  let #(next, actions) =
    state.update(
      helpers.init_default(),
      state.ArtifactFileRead(Error("unreadable file")),
    )
  assert Some("unreadable file") == next.artifact_import_error
  assert art.new() == next.artifacts
  assert [] == actions
}
