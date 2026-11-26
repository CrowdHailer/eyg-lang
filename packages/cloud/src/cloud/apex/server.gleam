import cloud/apex/context
import cloud/apex/router
import cloud/config.{Config}
import mist
import wisp
import wisp/wisp_mist

pub fn start(config, conn, wrap_reload) {
  build(config, conn, wrap_reload)
  |> mist.start
}

pub fn supervised(config, conn, wrap_reload) {
  build(config, conn, wrap_reload)
  |> mist.supervised
}

fn build(config, conn, wrap_reload) {
  wisp.configure_logger()
  let Config(secret_key_base:, ..) = config

  let context = context.from_config(config, conn)

  router.route(_, context)
  |> wisp_mist.handler(secret_key_base)
  |> wrap_reload()
  |> mist.new
  // Need 0.0.0.0 to work in docker
  |> mist.bind("0.0.0.0")
  |> mist.port(8080)
}
/// The server module is where we start a process and move from functional core to describing OTP trees
