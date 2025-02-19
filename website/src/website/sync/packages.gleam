import gleam/http/request
import website/sync/sync

// should be fetch from storage or remote but storage is only for self
pub fn fetch_remote(origin, group, name) {
  let path = "/packages/" <> group <> "/" <> name <> ".json"
  do_fetch_source(origin, path)
}

fn do_fetch_source(origin, path) {
  let assert Ok(origin) = request.from_uri(origin)
  let request =
    origin
    |> request.set_path(path)
    |> request.set_body(<<>>)
  sync.send_fetch_request(request)
}
