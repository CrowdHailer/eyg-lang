import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/store
import eyg/cli/system
import filepath
import gleam/json
import gleam/list
import gleam/string
import multiformats/cid/v1
import untethered/ledger/schema

pub fn initial(
  alias: String,
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  let config.Config(client:, dirs:) = config
  use keypair <- system.then(system.generate_key())
  use first <- system.then(client.initialise_principal(keypair, client))
  use first <- system.try(first)
  use first <- system.try(first)

  let principal = first.entity
  let s = store.Signatory(alias:, principal:, keypair:)
  use saved <- system.then(store.save_signatory(s, dirs))
  use Nil <- system.try(saved)

  use x <- system.then(client.pull_principal(client))
  use x <- system.try(x)
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

  use created <- system.then(
    system.create_directory(filepath.directory_name(path)),
  )
  use Nil <- system.try(created)
  use written <- system.then(system.write_file(path, cache))
  use Nil <- system.try(written)
  use Nil <- system.then(system.stdout("created signatory '" <> alias <> "'"))
  use Nil <- system.then(system.stdout("principal " <> v1.to_string(principal)))
  system.Done(Ok(0))
}
