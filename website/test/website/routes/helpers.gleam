import spotless/origin
import website/config

pub fn config() {
  config.Config(registry_origin: origin.https("eyg.test"))
}
