import harness/impl/spotless.{Config}
import harness/impl/spotless/netlify
import plinth/browser/window

pub fn load() {
  case window.origin() {
    "http://localhost:8080" ->
      Config(dnsimple_local: True, netlify: netlify.local, twitter_local: True)
    "https://eyg.run" ->
      Config(
        dnsimple_local: False,
        netlify: netlify.eyg_website,
        twitter_local: False,
      )
    _ -> panic as "No apps configured"
  }
}
