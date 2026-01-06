import spotless/origin
import website/config

pub fn config() {
  config.Config(origin: origin.https("eyg.test"))
}
