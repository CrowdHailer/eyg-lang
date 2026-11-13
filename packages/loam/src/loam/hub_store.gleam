//// Cache verified hub responses while retaining the normal cache protocol.

import eyg/hub/cache
import filepath
import gleam/http/response
import gleam/int
import loam/system
import multiformats/cid/v1
import simplifile

pub fn compute(action: cache.Action, origin, store: String) {
  case action {
    cache.FetchModule(cid) -> {
      let path = store <> "/modules/" <> v1.to_string(cid)
      use stored <- system.then(read(path))
      case stored {
        Ok(body) -> {
          use completed <- system.then(cached(action, origin, body))
          case valid(completed) {
            True -> system.Done(completed)
            False -> network(action, origin, path, False)
          }
        }
        Error(_) -> network(action, origin, path, False)
      }
    }
    cache.PullPackages(offset) ->
      network(
        action,
        origin,
        store <> "/packages/" <> int.to_string(offset),
        True,
      )
  }
}

fn cached(action, origin, body) {
  cache.compute(
    action,
    origin,
    fn(_) {
      fn(done) { done(Ok(response.new(200) |> response.set_body(body))) }
    },
    fn(algorithm, bytes) { fn(done) { system.Hash(algorithm, bytes, done) } },
  )(system.Done)
}

fn network(action, origin, path, mutable) {
  cache.compute(
    action,
    origin,
    fn(request) {
      fn(done) {
        use fetched <- system.then(system.fetch(request))
        case fetched, mutable {
          Error(_), True -> {
            use stored <- system.then(read(path))
            case stored {
              Ok(body) -> done(Ok(response.new(200) |> response.set_body(body)))
              Error(_) -> done(fetched)
            }
          }
          _, _ -> {
            use completed <- system.then(done(fetched))
            case fetched, valid(completed) {
              Ok(response), True if response.status == 200 -> {
                use _ <- system.then(
                  system.create_directory(filepath.directory_name(path)),
                )
                use _ <- system.map(system.write_file_bits(path, response.body))
                completed
              }
              _, _ -> system.Done(completed)
            }
          }
        }
      }
    },
    fn(algorithm, bytes) { fn(done) { system.Hash(algorithm, bytes, done) } },
  )(system.Done)
}

fn valid(completed) {
  case completed {
    cache.FetchModuleCompleted(_, Ok(_)) | cache.PullPackagesCompleted(Ok(_)) ->
      True
    _ -> False
  }
}

fn read(path) {
  use info <- system.then(system.file_info(path))
  case info {
    Ok(system.Metadata(simplifile.File, size)) -> {
      use body <- system.map(system.read_file_range(path, 0, size))
      case body {
        Ok(body) -> Ok(body)
        Error(_) -> Error(Nil)
      }
    }
    _ -> system.Done(Error(Nil))
  }
}
