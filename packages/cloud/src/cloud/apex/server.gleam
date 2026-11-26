import cloud/apex/context
import cloud/apex/router
import howdy

pub fn start(config, conn) {
  build(config, conn)
  |> howdy.start
}

pub fn supervised(config, conn) {
  build(config, conn)
  |> howdy.supervised
}

fn build(config, conn) {
  // let Config(secret_key_base:, ..) = config
  let context = context.from_config(config, conn)

  howdy.new()
  |> howdy.bind(to: "0.0.0.0")
  |> howdy.controller(router.route(context))
}
/// The server module is where we start a process and move from functional core to describing OTP trees
