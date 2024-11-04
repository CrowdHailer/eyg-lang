import gleam/int
import midas/sdk/dnsimple

pub fn authenticate(local) {
  let state = int.to_string(int.random(1_000_000_000))
  let state = case local {
    True -> "LOCAL" <> state
    False -> state
  }
  dnsimple.do_authenticate(eyg_website, state)
}

pub const eyg_website = dnsimple.App(
  "3b211050009f7553",
  "hidden",
  "https://eyg.run/auth/dnsimple",
)
