import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/element/keyed
import lustre/event
import overlay/public/artifact_preview
import overlay/web/artifact as art
import overlay/web/artifact/session
import overlay/web/puppet
import overlay/web/state
import plinthx/browser/file

pub fn render(model: state.State) -> element.Element(state.Message) {
  let store = model.artifacts
  let status = model.artifact_storage
  let dirty = model.artifacts_dirty
  h.section(
    [
      a.class("artifact-workspace"),
      a.classes([
        #(
          "empty",
          list.is_empty(store.panels)
            && dict.size(store.versions) == 0
            && status == session.Saved,
        ),
      ]),
      a.attribute("aria-label", "Artifacts"),
    ],
    [
      h.div([a.class("workspace-heading")], [h.text("ARTIFACT WORKSPACE")]),
      storage_status(store, status, dirty),
      transfer_controls(model),
      case store.panels {
        [] -> library(store)
        panels ->
          keyed.div(
            [a.class("artifact-canvas")],
            list.map(panels, fn(placement) {
              #(string.inspect(placement.item), panel(store, placement))
            }),
          )
      },
    ],
  )
}

fn transfer_controls(model: state.State) {
  h.div([a.class("artifact-transfer")], [
    case dict.size(model.artifacts.versions) {
      0 -> {
        let busy = case model.status {
          state.Waiting -> False
          _ -> True
        }
        h.label([], [
          h.span([], [h.text("Import workspace")]),
          h.input([
            a.type_("file"),
            a.attribute("accept", ".json,application/json"),
            a.attribute("aria-label", "Import workspace"),
            a.disabled(busy),
            event.on(
              "change",
              decode.map(
                decode.at(["target", "files", "0"], decode.dynamic),
                fn(raw) {
                  case file.from_dynamic(raw) {
                    Ok(file) -> state.UserSelectedArtifactFile(file)
                    Error(Nil) -> state.Ignore
                  }
                },
              ),
            ),
          ]),
        ])
      }
      _ ->
        h.button([event.on_click(state.UserExportedArtifacts)], [
          h.text("Download workspace"),
        ])
    },
    case model.artifact_import_error {
      None -> element.none()
      Some(reason) -> h.p([a.attribute("role", "alert")], [h.text(reason)])
    },
  ])
}

fn library(store: art.Store) {
  case dict.to_list(store.versions) {
    [] ->
      h.div([a.class("artifact-empty")], [
        h.p([], [h.text("Artifacts the agent shows appear here.")]),
        h.p([], [h.text("Each runs sandboxed, without network or storage.")]),
      ])
    versions ->
      h.div([a.class("artifact-empty")], [
        h.p([], [h.text("Your artifacts are still here.")]),
        h.p([], [h.text("Open a preview or revisit its history.")]),
        h.ul(
          [
            a.class("artifact-library"),
            a.attribute("aria-label", "Saved artifacts"),
          ],
          versions
            |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
            |> list.map(fn(entry) {
              let #(name, versions) = entry
              let count = list.length(versions)
              let label = case count {
                1 -> "1 version"
                _ -> int.to_string(count) <> " versions"
              }
              h.li([], [
                h.div([], [
                  h.strong([], [h.text(name)]),
                  h.span([], [h.text(label)]),
                ]),
                h.div([a.class("artifact-library-actions")], [
                  open_button("Open", "Open " <> name, art.Artifact(name)),
                  open_button(
                    "History",
                    "History of " <> name,
                    art.History(name),
                  ),
                ]),
              ])
            }),
        ),
      ])
  }
}

fn open_button(label, accessible_label, item) {
  h.button(
    [
      a.attribute("aria-label", accessible_label),
      event.on_click(
        state.UserShowedArtifact(art.Placement(
          item,
          art.Point(0, 0),
          art.Point(1000, 1000),
        )),
      ),
    ],
    [h.text(label)],
  )
}

fn storage_status(store: art.Store, status, dirty) {
  let content = case status {
    session.SaveFailed(reason) -> [
      h.text(
        "Changes could not be saved in this tab. Keep it open to retain them. ",
      ),
      h.button(
        [a.title(reason), event.on_click(state.UserRetriedArtifactSave)],
        [h.text("Retry saving")],
      ),
    ]
    session.RestoreFailed(reason) -> [
      h.text("Saved artifacts could not be restored: " <> reason),
    ]
    _ ->
      case dict.size(store.versions), dirty, status {
        0, _, _ -> []
        _, True, _ -> [h.text("Unsaved changes")]
        _, _, session.Saving -> [h.text("Saving…")]
        _, _, _ -> [h.text("Saved in this tab")]
      }
  }
  h.div([a.class("artifact-storage"), a.attribute("role", "status")], content)
}

fn percent(n) {
  int.to_string(n / 10) <> "." <> int.to_string(n % 10) <> "%"
}

fn panel(store: art.Store, placement: art.Placement) {
  let art.Placement(item, origin, size) = placement
  let style =
    "left:"
    <> percent(origin.x)
    <> ";top:"
    <> percent(origin.y)
    <> ";width:"
    <> percent(size.x)
    <> ";height:"
    <> percent(size.y)
  h.article([a.class("artifact-panel"), a.attribute("style", style)], [
    h.header([a.class("artifact-heading")], [
      h.span([], [h.text(art.title(item))]),
      case art.version(store, item) {
        Ok(#(_, version, _)) ->
          h.span([a.class("artifact-version")], [
            h.text("v" <> int.to_string(version)),
          ])
        Error(Nil) -> element.none()
      },
      case item {
        art.Artifact(name) ->
          h.button(
            [
              a.title("Show revision history"),
              event.on_click(
                state.UserShowedArtifact(art.Placement(
                  art.History(name),
                  origin,
                  size,
                )),
              ),
            ],
            [h.text("history")],
          )
        _ -> element.none()
      },
      share(store, item),
      h.button(
        [
          a.attribute("aria-label", "Close " <> art.title(item)),
          event.on_click(state.UserClosedArtifact(item)),
        ],
        [h.text("×")],
      ),
    ]),
    case item {
      art.Artifact(name) -> preview(art.latest(store, name), item)
      art.Revision(name, version) ->
        preview(art.revision(store, name, version), item)
      art.History(name) -> history(store, name, origin, size)
      art.Diff(name, from, to) -> diff(store, name, from, to)
    },
  ])
}

/// Sharing is always a choice of the person, an agent cannot share an artifact.
fn share(store: art.Store, item) {
  case art.version(store, item) {
    Error(Nil) -> element.none()
    Ok(#(name, version, _bundle)) -> {
      let version_label = "v" <> int.to_string(version)
      case dict.get(store.shares, #(name, version)) {
        Error(Nil) ->
          h.button(
            [
              a.title("Share " <> version_label <> " as a public link"),
              event.on_click(state.UserClickedShare(item)),
            ],
            [h.text("share")],
          )
        Ok(art.Sharing) ->
          h.span([a.class("artifact-share")], [h.text("sharing…")])
        Ok(art.Shared(id:, ..)) ->
          h.a(
            [
              a.class("artifact-share"),
              a.href("/artifact/" <> id),
              a.target("_blank"),
              a.rel("noopener"),
              a.title("Open the shared " <> version_label),
            ],
            [h.text("shared ↗")],
          )
        Ok(art.ShareFailed(reason)) ->
          h.button(
            [a.title(reason), event.on_click(state.UserClickedShare(item))],
            [h.text("retry share")],
          )
      }
    }
  }
}

fn preview(bundle, item) {
  case bundle {
    Error(reason) -> h.pre([], [h.text(reason)])
    // Preparing a bundle inlines every file, only repeat it for a new bundle.
    Ok(bundle) -> {
      let title = art.title(item)
      use <- element.memo([element.ref(bundle), element.ref(title)])
      let frame =
        list.map(puppet.frame_attributes(item), fn(attribute) {
          a.attribute(attribute.0, attribute.1)
        })
      element.element(
        "iframe",
        [
          a.class("artifact-preview"),
          a.title(title),
          a.attribute("sandbox", "allow-scripts"),
          a.attribute("referrerpolicy", "no-referrer"),
          a.attribute("srcdoc", artifact_preview.srcdoc(bundle)),
          a.attribute(
            "allow",
            "camera 'none'; microphone 'none'; geolocation 'none'; clipboard-read 'none'; clipboard-write 'none'",
          ),
          ..frame
        ],
        [],
      )
    }
  }
}

fn history(store, name, origin, size) {
  let versions = art.history(store, name)
  let count = list.length(versions)
  h.div(
    [a.class("artifact-inspector")],
    list.index_map(versions, fn(bundle, i) {
      let version = count - i
      h.section([a.class("artifact-revision")], [
        h.button(
          [
            event.on_click(
              state.UserShowedArtifact(art.Placement(
                art.Revision(name, version),
                origin,
                size,
              )),
            ),
          ],
          [
            h.text("Open v" <> int.to_string(version)),
          ],
        ),
        case version > 1 {
          True ->
            h.button(
              [
                event.on_click(
                  state.UserShowedArtifact(art.Placement(
                    art.Diff(name, version - 1, version),
                    origin,
                    size,
                  )),
                ),
              ],
              [h.text("Compare with previous")],
            )
          False -> element.none()
        },
        h.ul(
          [],
          list.map(bundle, fn(file) {
            h.li([], [
              h.text(
                file.path
                <> " · "
                <> int.to_string(bit_array.byte_size(file.content))
                <> " bytes",
              ),
            ])
          }),
        ),
      ])
    }),
  )
}

fn diff(store, name, from, to) {
  case art.revision(store, name, from), art.revision(store, name, to) {
    Ok(before), Ok(after) -> {
      let changes = art.diff(before, after)
      h.div([a.class("artifact-inspector")], case changes {
        [] -> [h.text("No file changes.")]
        _ ->
          list.map(changes, fn(change) {
            case change {
              art.Added(file) ->
                h.section([], [
                  h.h3([], [h.text("Added " <> file.path)]),
                  file_text(file, "+"),
                ])
              art.Removed(file) ->
                h.section([], [
                  h.h3([], [h.text("Removed " <> file.path)]),
                  file_text(file, "−"),
                ])
              art.Changed(before, after) ->
                h.section([], [
                  h.h3([], [h.text("Changed " <> after.path)]),
                  h.p([], [
                    h.text(before.media_type <> " → " <> after.media_type),
                  ]),
                  file_text(before, "−"),
                  file_text(after, "+"),
                ])
            }
          })
      })
    }
    _, _ -> h.text("Revision unavailable")
  }
}

fn file_text(file: art.File, prefix) {
  let text = case bit_array.to_string(file.content) {
    Ok(text) ->
      string.split(text, "\n")
      |> list.map(fn(line) { prefix <> " " <> line })
      |> string.join("\n")
    Error(_) ->
      prefix
      <> " Binary: "
      <> int.to_string(bit_array.byte_size(file.content))
      <> " bytes"
  }
  h.pre(
    [
      a.class(case prefix {
        "+" -> "diff-added"
        _ -> "diff-removed"
      }),
    ],
    [h.text(text)],
  )
}
