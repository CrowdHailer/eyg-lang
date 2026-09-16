import gleam/bit_array
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/element/keyed
import lustre/event
import overlay/web/artifact as art
import overlay/web/state

@external(javascript, "./artifact_preview.mjs", "prepare")
fn prepare(bundle: art.Bundle, encode: fn(art.Bundle) -> String) -> String

fn encode(bundle: art.Bundle) -> String {
  json.array(bundle, fn(file) {
    json.object([
      #("path", json.string(file.path)),
      #("media_type", json.string(file.media_type)),
      #("content", json.string(bit_array.base64_encode(file.content, True))),
    ])
  })
  |> json.to_string
}

pub fn render(store: art.Store) -> element.Element(state.Message) {
  case store.panels {
    [] -> element.none()
    panels ->
      h.section(
        [a.class("artifact-workspace"), a.attribute("aria-label", "Artifacts")],
        [
          h.div([a.class("workspace-heading")], [h.text("ARTIFACT WORKSPACE")]),
          keyed.div(
            [a.class("artifact-canvas")],
            list.map(panels, fn(placement) {
              #(string.inspect(placement.item), panel(store, placement))
            }),
          ),
        ],
      )
  }
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
      h.button(
        [
          a.attribute("aria-label", "Close " <> art.title(item)),
          event.on_click(state.UserClosedArtifact(item)),
        ],
        [h.text("×")],
      ),
    ]),
    case item {
      art.Artifact(name) -> preview(art.latest(store, name), art.title(item))
      art.Revision(name, version) ->
        preview(art.revision(store, name, version), art.title(item))
      art.History(name) -> history(store, name, origin, size)
      art.Diff(name, from, to) -> diff(store, name, from, to)
    },
  ])
}

fn preview(bundle, title) {
  case bundle {
    Error(reason) -> h.pre([], [h.text(reason)])
    Ok(bundle) ->
      element.element(
        "iframe",
        [
          a.class("artifact-preview"),
          a.title(title),
          a.attribute("sandbox", "allow-scripts"),
          a.attribute("referrerpolicy", "no-referrer"),
          a.attribute("srcdoc", prepare(bundle, encode)),
          a.attribute(
            "allow",
            "camera 'none'; microphone 'none'; geolocation 'none'; clipboard-read 'none'; clipboard-write 'none'",
          ),
        ],
        [],
      )
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
