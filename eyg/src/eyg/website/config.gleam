import harness/impl/spotless.{Config}
import harness/impl/spotless/dnsimple
import harness/impl/spotless/netlify
import plinth/browser/window

pub fn load() {
  case window.origin() {
    "http://localhost:8080" ->
      Config(dnsimple: dnsimple.local, netlify: netlify.local)
    "https://eyg.run" ->
      Config(dnsimple: dnsimple.eyg_website, netlify: netlify.eyg_website)
    _ -> panic as "No apps configured"
  }
}
