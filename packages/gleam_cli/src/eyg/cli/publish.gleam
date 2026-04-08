import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/source
import eyg/cli/internal/store
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/option.{None, Some}
import untethered/ledger/schema

pub fn execute(package, file, config) {
  let config.Config(client:, dirs:) = config
  use signatories <- promisex.try_sync(store.all_signatories(dirs))
  use signatory <- promisex.try_sync(case signatories {
    [] -> Error("No signatories created.")
    [signatory] -> Ok(signatory)
    _ -> Error("Multiple signatories created")
  })
  use source <- promisex.try_sync(source.read(file))
  use module <- promise.try_await(client.share_module(source, config.client))

  use history <- promise.try_await(client.pull_package(client, package))
  let previous = case history.entries {
    [] -> None
    [schema.ArchivedEntry(cid:, sequence:, ..), ..] -> Some(#(sequence, cid))
  }
  // Lookup package state from cache
  use _response <- promise.try_await(client.submit_release(
    signatory,
    package,
    module,
    previous,
    client,
  ))
  promise.resolve(Ok("published"))
}
