import hub/config.{Config}
import hub/router
import hub/server/context
import mist
import wisp
import wisp/wisp_mist

pub fn start(config, db, wrap_reload) {
  build(config, db, wrap_reload)
  |> mist.start
}

pub fn supervised(config, db, wrap_reload) {
  build(config, db, wrap_reload)
  |> mist.supervised
}

fn build(config, db, wrap_reload) {
  wisp.configure_logger()
  let Config(secret_key_base:, ..) = config

  let context = context.from_config(config, db)

  router.route(_, context)
  |> wisp_mist.handler(secret_key_base)
  |> wrap_reload()
  |> mist.new
  // Need 0.0.0.0 to work in docker
  |> mist.bind("0.0.0.0")
  |> mist.port(8080)
}
