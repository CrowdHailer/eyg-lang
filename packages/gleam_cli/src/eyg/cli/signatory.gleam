import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/crypto
import eyg/cli/internal/store
import filepath
import gleam/javascript/promise.{type Promise}
import gleam/javascript/promisex
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import multiformats/cid/v1
import simplifile
import untethered/ledger/schema

pub fn initial(
  alias: String,
  config: config.Config,
) -> Promise(Result(Nil, String)) {
  let config.Config(client:, dirs:) = config
  let keypair = crypto.generate_key()
  use first <- promise.try_await(client.initialise_principal(keypair, client))
  use first <- promisex.try_sync(first)

  let principal = first.entity
  let s = store.Signatory(alias:, principal:, keypair:)
  use Nil <- promisex.try_sync(
    store.save_signatory(s, dirs)
    |> result.map_error(simplifile.describe_error),
  )

  use x <- promise.try_await(client.pull_principal(client))
  let events =
    list.filter(x.entries, fn(entry) { entry.entity == first.entity })

  let cache =
    list.map(events, schema.archived_entry_encode)
    |> list.map(json.to_string)
    |> string.join("\r\n")

  let path =
    dirs.cache_dir
    <> "/eyg/principals/"
    <> v1.to_string(first.entity)
    <> ".json"

  let assert Ok(Nil) =
    simplifile.create_directory_all(filepath.directory_name(path))

  simplifile.write(path, cache)
  |> result.replace(Nil)
  |> result.map_error(simplifile.describe_error)
  |> promise.resolve
}
