import hub/config

pub type Context {
  Context(secret_key_base: String)
}

pub fn from_config(config) {
  let config.Config(secret_key_base:) = config
  Context(secret_key_base:)
}
