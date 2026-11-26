import cloud/config
import pog

pub type Context {
  Context(secret_key_base: String, conn: pog.Connection)
}

pub fn from_config(config, conn) {
  let config.Config(secret_key_base:, ..) = config
  Context(secret_key_base:, conn:)
}
