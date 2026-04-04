import hub/config
import pog

pub type Context {
  Context(secret_key_base: String, db: pog.Connection)
}

pub fn from_config(config, db) {
  let config.Config(secret_key_base:, ..) = config
  Context(secret_key_base:, db:)
}
