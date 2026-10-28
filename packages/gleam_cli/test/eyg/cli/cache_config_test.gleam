import eyg/cli/helpers
import eyg/cli/internal/client
import eyg/cli/internal/config
import gleam/http
import gleam/list
import gleam/option.{None, Some}
import ogre/origin

pub fn cache_origins_keep_scheme_and_port_distinct_test() {
  let base = helpers.config
  let urls = [
    origin.Origin(http.Http, "hub.test", None),
    origin.Origin(http.Https, "hub.test", None),
    origin.Origin(http.Http, "hub.test", Some(8000)),
    origin.Origin(http.Http, "hub.test_8000", None),
  ]
  let assert [a, b, c, d] = {
    use url <- list.map(urls)
    config.hub_store(config.Config(..base, client: client.Client(url)))
  }
  assert a != b && a != c && a != d && b != c && b != d && c != d
}
