//// Validated, versioned snapshots for tab-local artifact recovery.
//// Only completed shares are retained; an interrupted share can be retried.

import eyg/hub/schema
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import overlay/web/artifact as art

pub type Status {
  Saved
  Saving
  SaveFailed(String)
  RestoreFailed(String)
}

pub fn encode(store: art.Store) -> String {
  let revisions =
    dict.to_list(store.versions)
    |> list.flat_map(fn(entry) {
      let #(name, versions) = entry
      versions
      |> list.reverse
      |> list.map(fn(bundle) {
        schema.artifact_encode(
          name,
          list.map(bundle, fn(file) {
            schema.ArtifactFile(file.path, file.media_type, file.content)
          }),
        )
      })
    })
  let shares =
    dict.to_list(store.shares)
    |> list.filter_map(fn(entry) {
      case entry {
        #(#(name, version), art.Shared(id, secret)) ->
          Ok(
            json.object([
              #("name", json.string(name)),
              #("version", json.int(version)),
              #(
                "shared",
                schema.shared_artifact_encode(schema.SharedArtifact(id, secret)),
              ),
            ]),
          )
        _ -> Error(Nil)
      }
    })
  json.object([
    #("format", json.int(1)),
    #("revisions", json.array(revisions, fn(x) { x })),
    #("panels", json.array(store.panels, panel_json)),
    #("shares", json.array(shares, fn(x) { x })),
  ])
  |> json.to_string
}

fn panel_json(panel: art.Placement) {
  let #(kind, name, from, to) = case panel.item {
    art.Artifact(name) -> #("artifact", name, 0, 0)
    art.Revision(name, version) -> #("revision", name, version, 0)
    art.History(name) -> #("history", name, 0, 0)
    art.Diff(name, from, to) -> #("diff", name, from, to)
  }
  json.object([
    #("kind", json.string(kind)),
    #("name", json.string(name)),
    #("from", json.int(from)),
    #("to", json.int(to)),
    #("x", json.int(panel.origin.x)),
    #("y", json.int(panel.origin.y)),
    #("width", json.int(panel.size.x)),
    #("height", json.int(panel.size.y)),
  ])
}

pub fn restore(stored: String) -> Result(art.Store, String) {
  use #(revisions, panels, shares) <- result.try(
    json.parse(stored, decoder())
    |> result.replace_error(
      "Saved artifacts use an unreadable or unsupported format",
    ),
  )
  // Reuse live validation for paths, sizes, media types and total history size.
  use store <- result.try(
    list.try_fold(revisions, art.new(), fn(store, revision) {
      let #(name, files) = revision
      let bundle =
        list.map(files, fn(file) {
          art.File(file.path, file.media_type, file.content)
        })
      art.save(store, name, bundle) |> result.map(fn(saved) { saved.0 })
    }),
  )
  use store <- result.try(list.try_fold(panels, store, art.show))
  list.try_fold(shares, store, fn(store, entry) {
    let #(name, version, shared) = entry
    use _ <- result.try(art.revision(store, name, version))
    Ok(art.share(store, name, version, art.Shared(shared.id, shared.secret)))
  })
}

fn decoder() {
  use format <- decode.field("format", decode.int)
  use _ <- decode.then(case format {
    1 -> decode.success(Nil)
    _ -> decode.failure(Nil, "artifact workspace format 1")
  })
  use revisions <- decode.field(
    "revisions",
    decode.list(schema.artifact_decoder()),
  )
  use panels <- decode.field("panels", decode.list(panel_decoder()))
  use shares <- decode.field("shares", decode.list(share_decoder()))
  decode.success(#(revisions, panels, shares))
}

fn panel_decoder() {
  use kind <- decode.field("kind", decode.string)
  use name <- decode.field("name", decode.string)
  use from <- decode.field("from", decode.int)
  use to <- decode.field("to", decode.int)
  use x <- decode.field("x", decode.int)
  use y <- decode.field("y", decode.int)
  use width <- decode.field("width", decode.int)
  use height <- decode.field("height", decode.int)
  use item <- decode.then(case kind {
    "artifact" -> decode.success(art.Artifact(name))
    "revision" -> decode.success(art.Revision(name, from))
    "history" -> decode.success(art.History(name))
    "diff" -> decode.success(art.Diff(name, from, to))
    _ -> decode.failure(art.Artifact(""), "artifact panel kind")
  })
  decode.success(art.Placement(item, art.Point(x, y), art.Point(width, height)))
}

fn share_decoder() {
  use name <- decode.field("name", decode.string)
  use version <- decode.field("version", decode.int)
  use shared <- decode.field("shared", schema.shared_artifact_decoder())
  decode.success(#(name, version, shared))
}

/// A portable copy contains files and layout, without ownership secrets.
pub fn export(store: art.Store) -> String {
  encode(art.Store(..store, shares: dict.new()))
}

pub fn import_copy(stored: String) -> Result(art.Store, String) {
  restore(stored)
  |> result.map(fn(store) { art.Store(..store, shares: dict.new()) })
}
