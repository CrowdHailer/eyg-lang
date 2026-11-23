//// The web interface, a page with the terminal interface on it.
//// Each connection runs its own terminal interface on the server, the page only draws it and sends keys.
////
//// Artifacts are files of a box read by the root of the box's files, `/artifacts/:root/*path`.
//// They are written by shells and so are not trusted. Each is a sandbox with its own origin,
//// its scripts run but cannot read the site, see `server` for how requests from a sandbox are refused.

import cloud/apex/api
import cloud/apex/context.{type Context}
import cloud/apex/terminal
import cloud/apex/tui
import cloud/artifacts
import gleam/bytes_tree
import gleam/http/response
import gleam/result
import howdy/content
import howdy/controller
import howdy/ui/live
import howdy/ui/page
import lustre/attribute
import lustre/element/html
import multiformats/cid/v1

pub fn page(ctx: controller.Context) {
  page.new("EYG cloud")
  |> page.live
  // Phones do not enlarge the text of the terminal, so it fits the cells measured for it.
  |> page.head([
    html.style(
      [],
      "html { -webkit-text-size-adjust: 100%; text-size-adjust: 100%; } body { margin: 0; background: #181818; }",
    ),
  ])
  |> page.body([html.script([attribute.type_("module")], terminal.script)])
  |> page.body([live.mount("/tui")])
  |> page.respond(ctx)
}

/// The terminal interface of a connection, the page mounts it.
pub fn tui(ctx: controller.Context, context: Context) {
  live.serve(ctx, tui.app(), with: context)
}

pub fn artifact(root, path, context: Context) {
  let file = {
    use #(root, _) <- result.try(
      v1.from_string(root) |> result.replace_error(Nil),
    )
    artifacts.read(root, path, context.state)
  }
  case file {
    Ok(bytes) ->
      response.new(200)
      |> response.set_body(content.Bytes(bytes_tree.from_bit_array(bytes)))
      |> response.set_header("content-type", artifacts.content_type(path))
      |> response.set_header("content-security-policy", "sandbox allow-scripts")
      |> response.set_header("x-content-type-options", "nosniff")
      // A root never changes.
      |> response.set_header(
        "cache-control",
        "private, max-age=31536000, immutable",
      )
    Error(Nil) -> api.status(404)
  }
}
