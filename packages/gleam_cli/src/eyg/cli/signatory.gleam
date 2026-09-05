import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/store
import eyg/cli/system
import eyg/hub/signatory as principal
import filepath
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import kryptos/eddsa
import multiformats/cid/v1
import ogre/origin
import untethered/ledger/schema

pub fn initial(
  alias: String,
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use Nil <- system.try(store.validate_alias(alias))
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

pub fn list(config: config.Config) -> system.Effect(Result(Int, String)) {
  use aliases <- system.then(store.signatory_aliases(config.dirs))
  use aliases <- system.try(aliases)
  case aliases {
    [] -> {
      use Nil <- system.then(system.stdout("No local signatories."))
      system.Done(Ok(0))
    }
    _ -> {
      use loaded <- system.then(load_aliases(aliases, config, []))
      let principals =
        loaded
        |> list.filter_map(fn(item) {
          result.map(item.1, fn(signatory) { signatory.principal })
        })
        |> list.unique
      use pulled <- system.then(case principals {
        [] -> system.Done(Ok([]))
        _ -> client.pull_signatories(principals, config.client)
      })
      let output =
        list.map(loaded, fn(item) {
          let #(alias, loaded) = item
          case loaded {
            Error(reason) ->
              "Alias: " <> string.inspect(alias) <> "\nError: " <> reason
            Ok(signatory) ->
              metadata(signatory, config, history(pulled, signatory.principal))
          }
        })
      use Nil <- system.then(system.stdout(string.join(output, "\n\n")))
      let status = case list.any(loaded, fn(item) { result.is_error(item.1) }) {
        True -> 1
        False -> 0
      }
      system.Done(Ok(status))
    }
  }
}

pub fn show(
  alias: String,
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use loaded <- system.then(store.read_signatory(alias, config.dirs))
  use signatory <- system.try(
    result.map_error(loaded, fn(reason) {
      "signatory " <> string.inspect(alias) <> ": " <> reason
    }),
  )
  use pulled <- system.then(client.pull_signatories(
    [signatory.principal],
    config.client,
  ))
  let history = history(pulled, signatory.principal)
  use Nil <- system.then(system.stdout(metadata(signatory, config, history)))
  use events <- system.try(history)
  let output =
    list.map(events, fn(item) {
      let #(archive, entry) = item
      let affected = case entry.content {
        principal.AddKey(key) | principal.RemoveKey(key) -> key
      }
      string.join(
        [
          "Event " <> int.to_string(archive.sequence) <> ": " <> archive.type_,
          "  CID: " <> v1.to_string(archive.cid),
          "  Principal CID: " <> v1.to_string(archive.entity),
          "  Cursor: " <> int.to_string(archive.cursor),
          "  Previous CID: "
            <> case archive.previous {
            None -> "none"
            Some(cid) -> v1.to_string(cid)
          },
          "  Signing key ID: " <> string.inspect(entry.key),
          "  Affected key ID: " <> string.inspect(affected),
          "  Payload: " <> string.inspect(archive.payload),
        ],
        "\n",
      )
    })
  use Nil <- system.then(system.stdout("\n" <> string.join(output, "\n\n")))
  system.Done(Ok(0))
}

fn load_aliases(aliases, config: config.Config, loaded) {
  case aliases {
    [] -> system.Done(list.reverse(loaded))
    [alias, ..rest] -> {
      use signatory <- system.then(store.read_signatory(alias, config.dirs))
      load_aliases(rest, config, [#(alias, signatory), ..loaded])
    }
  }
}

fn history(pulled: Result(List(schema.ArchivedEntry), String), cid: v1.Cid) {
  use entries <- result.try(pulled)
  let entries =
    entries
    |> list.filter(fn(entry) { entry.entity == cid })
    |> list.sort(fn(a, b) { int.compare(a.sequence, b.sequence) })
  case entries {
    [] -> Error("principal not found on configured hub")
    _ -> {
      use state <- result.try(
        list.try_fold(entries, #(1, None, [], dict.new()), fn(state, archive) {
          let #(sequence, previous, events, keys) = state
          use entry <- result.try(
            json.parse(archive.payload, principal.decoder())
            |> result.replace_error("invalid or unsupported signatory event"),
          )
          let #(type_, _) = principal.event_encode(entry.content)
          use Nil <- result.try(
            case
              archive.sequence == sequence
              && archive.previous == previous
              && entry.sequence == sequence
              && entry.previous == previous
              && archive.type_ == type_
              && { sequence != 1 || archive.cid == cid }
            {
              False -> Error("incomplete or inconsistent signatory history")
              True -> Ok(Nil)
            },
          )
          let authorized = case sequence, entry.content {
            1, principal.AddKey(key) -> entry.key == key
            1, principal.RemoveKey(_) -> False
            _, _ -> dict.has_key(keys, entry.key)
          }
          case authorized {
            False -> Error("invalid or unauthorized signatory event")
            True -> {
              let keys = case entry.content {
                principal.AddKey(key) -> dict.insert(keys, key, Nil)
                principal.RemoveKey(key) -> dict.delete(keys, key)
              }
              Ok(#(
                sequence + 1,
                Some(archive.cid),
                [#(archive, entry), ..events],
                keys,
              ))
            }
          }
        }),
      )
      Ok(list.reverse(state.2))
    }
  }
}

fn metadata(
  signatory: store.Signatory,
  config: config.Config,
  history: Result(List(#(schema.ArchivedEntry, principal.Entry)), String),
) {
  let assert Ok(der) = eddsa.public_key_to_der(signatory.keypair.public_key)
  let fingerprint =
    crypto.hash(crypto.Sha256, der)
    |> bit_array.base64_encode(False)
  let status = case history {
    Error(reason) -> [
      "Local key in principal: unknown",
      "Hub status: " <> reason,
    ]
    Ok(events) -> {
      let keys =
        events
        |> list.map(fn(item) { item.1.content })
        |> principal.state
      let membership = case dict.has_key(keys, signatory.keypair.key_id) {
        True -> "present"
        False -> "absent"
      }
      let assert Ok(#(latest, _)) = list.last(events)
      [
        "Local key in principal: " <> membership,
        "Hub status: registered (history retrieved from configured hub)",
        "Events: " <> int.to_string(list.length(events)),
        "Latest sequence: " <> int.to_string(latest.sequence),
        "Latest event CID: " <> v1.to_string(latest.cid),
      ]
    }
  }
  string.join(
    [
      "Alias: " <> string.inspect(signatory.alias),
      "Principal CID: " <> v1.to_string(signatory.principal),
      "Key ID: " <> string.inspect(signatory.keypair.key_id),
      "Key fingerprint (SHA-256, public-key DER): SHA256:" <> fingerprint,
      "Credential file: "
        <> string.inspect(
        store.signatories_dir(config.dirs) <> signatory.alias <> ".json",
      ),
      "Principal cache file: "
        <> string.inspect(
        config.dirs.cache_dir
        <> "/eyg/principals/"
        <> v1.to_string(signatory.principal)
        <> ".json",
      ),
      "Hub: " <> origin.to_string(config.client.origin),
      ..status
    ],
    "\n",
  )
}
