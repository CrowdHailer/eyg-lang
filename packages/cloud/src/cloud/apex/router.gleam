import cloud/apex/api
import cloud/apex/context.{type Context}
import cloud/box/controller as boxes
import cloud/chats/api as chats
import cloud/shells/api as shells
import gleam/http
import gleam/http/request
import gleam/http/response.{type Response}
import gleam/list
import gleam/string
import howdy/content.{type Content}
import howdy/controller

/// howdy routes requests by patterns written as strings.
/// Every request is given to `route` instead, which matches on its path and method.
pub fn controller(context: Context) -> controller.Controller {
  [http.Get, http.Post, http.Put, http.Patch, http.Delete]
  |> list.fold(controller.new("/"), fn(controller, method) {
    controller.route(controller, method, "/*path", route(_, context))
  })
  |> controller.build
}

pub fn route(ctx: controller.Context, context: Context) -> Response(Content) {
  case request.path_segments(ctx.request), ctx.request.method {
    ["boxes"], http.Get -> boxes.list(context)
    ["boxes"], http.Post -> boxes.create(ctx, context)
    ["boxes", id], http.Get -> boxes.get(id, context)
    ["boxes", id, "files", ..path], method -> {
      let path = "/" <> string.join(path, "/")
      case method {
        http.Get -> boxes.read(id, path, context)
        http.Put -> boxes.write(ctx, id, path, context)
        http.Delete -> boxes.delete(id, path, context)
        _ ->
          api.status(405)
          |> response.set_header("allow", "GET, PUT, DELETE")
      }
    }
    ["boxes", id, "shells"], http.Post -> shells.create(id, context)
    ["boxes", id, "shells"], http.Get -> shells.list(id, context)
    ["shells", id], http.Get -> shells.get(id, context)
    ["shells", id, "events"], http.Get -> shells.export(id, context)
    ["shells", id, "fork"], http.Post -> shells.fork(id, context)
    ["shells", id, "trace"], http.Get -> shells.trace(id, context)
    ["shells", id, "turns"], http.Post -> shells.turn(ctx, id, context)
    ["boxes", id, "chats"], http.Post -> chats.create(ctx, id, context)
    ["boxes", id, "chats"], http.Get -> chats.list(id, context)
    ["boxes", id, "calls"], http.Post -> chats.calls(ctx, id, context)
    ["llms"], http.Get -> chats.llms(context)
    ["chats", id], http.Get -> chats.get(id, context)
    ["chats", id, "events"], http.Get -> chats.export(id, context)
    ["chats", id, "messages"], http.Post -> chats.send(ctx, id, context)
    ["chats", id, "trace"], http.Get -> chats.trace(id, context)
    _, _ -> api.status(404)
  }
}
