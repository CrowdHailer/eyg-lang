import cloud
import cloud/access
import cloud/api
import cloud/catalog
import cloud/connections
import cloud/discord/discord
import cloud/docs
import cloud/overlay
import cloud/slack/slack
import cloud/tui
import envoy
import gleam/erlang/process
import gleam/int
import gleam/result
import gleam/string
import howdy
import howdy/controller
import howdy/ui/live
import howdy/ui/page
import lustre/element/html as h

pub fn main() {
  let assert Ok(token) = envoy.get("EYG_CLOUD_TOKEN")
    as "Set EYG_CLOUD_TOKEN to your administrator token"
  let assert True = string.length(token) >= 24
    as "Use at least 24 characters for EYG_CLOUD_TOKEN"
  let directory = envoy.get("EYG_CLOUD_DATA") |> result.unwrap(".cloud")
  let #(runtime, llm) = cloud.setup()
  let assert Ok(catalog) = catalog.start(directory, runtime)
  let assert Ok(access) =
    access.start(directory <> "/account.json", token, runtime)
  let service =
    api.Service(catalog.data, access.data, overlay.setup(runtime.origin, llm))
  let assert Ok(bridge) = connections.start(service)
  case envoy.get("SLACK_BOT_TOKEN") {
    Ok(token) -> {
      let assert Ok(_) = slack.start_channel(bridge.data, token, [])
      Nil
    }
    Error(_) -> Nil
  }
  case envoy.get("DISCORD_BOT_TOKEN"), envoy.get("DISCORD_GUILD_ID") {
    Ok(token), Ok(guild) -> {
      let assert Ok(_) = discord.start_channel(bridge.data, token, guild, [])
      Nil
    }
    _, _ -> Nil
  }
  let port = envoy.get("PORT") |> result.try(int.parse) |> result.unwrap(8787)
  let bind = envoy.get("EYG_CLOUD_BIND") |> result.unwrap("127.0.0.1")
  let domain = envoy.get("EYG_CLOUD_DOMAIN") |> result.unwrap("eyg.cloud")
  let assert Ok(_) =
    app(service, domain)
    |> howdy.bind(bind)
    |> howdy.listening(port)
    |> howdy.start
  process.sleep_forever()
}

pub fn app(service, domain) {
  howdy.new()
  |> howdy.middleware(fn(ctx, next) {
    case string.ends_with(ctx.request.host, "." <> domain) {
      True ->
        api.public_request(
          ctx,
          service,
          string.drop_end(ctx.request.host, string.length(domain) + 1),
          ctx.request.path,
        )
      False -> next(ctx)
    }
  })
  |> howdy.controller(api.controller(service))
  |> howdy.controller(api.public_controller(service))
  |> howdy.controller(api.short_controller(service))
  |> howdy.controller(docs.controller())
  |> howdy.controller(
    controller.new("/")
    |> controller.get("/", fn(ctx) {
      page.new("EYG Cloud")
      |> page.live
      |> page.head([h.style([], css)])
      |> page.body([live.mount("/tui")])
      |> page.respond(ctx)
    })
    |> controller.get("/tui", fn(ctx) {
      live.serve(ctx, tui.app(), with: service)
    })
    |> controller.build,
  )
}

pub const css =
  "
html,body{margin:0;min-height:100%;background:#111923;color:#d5e4f1;font:15px/1.5 ui-monospace,monospace}
main{min-height:100vh;padding:1.5rem;box-sizing:border-box;max-width:1400px;margin:auto}
.terminal{color:#81e6bd;background:#0a1119;border:1px solid #345468;padding:1rem;overflow:auto;font:14px/1.35 monospace}
nav{display:flex;gap:.7rem;flex-wrap:wrap;align-items:center;border-bottom:1px solid #345468;padding:1rem 0}
a{color:#81c9ff}button,input,select,textarea{font:inherit;color:inherit;background:#1a2b3a;border:1px solid #557184;border-radius:3px;padding:.5rem}
button{cursor:pointer;margin:.25rem}button:hover,button:focus{background:#2a465b;border-color:#81e6bd}
label{display:block;margin:1rem 0}input,select{display:block;width:min(100%,650px)}textarea{display:block;width:100%;box-sizing:border-box}
aside{margin:1rem 0}section{padding:1rem 0}h2{color:#81e6bd}#status{padding:.7rem;background:#203346;overflow-wrap:anywhere}
.file-list{max-height:220px;overflow:auto}.file-list button{display:block}pre{white-space:pre-wrap;overflow-wrap:anywhere}
details{margin:1rem 0;border:1px solid #345468;padding:1rem}summary{cursor:pointer;color:#81e6bd}
"
