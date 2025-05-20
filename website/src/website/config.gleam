import plinth/browser/window
import website/harness/spotless.{Config}

pub fn load() {
  case window.origin() {
    "http://localhost:8080" -> Config(dnsimple_local: True, twitter_local: True)
    "https://eyg.run" -> Config(dnsimple_local: False, twitter_local: False)
    _ -> panic as "No apps configured"
  }
}
