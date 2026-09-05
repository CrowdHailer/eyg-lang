import envoy
import eyg/cli/internal/bun_platform
import eyg/cli/internal/crypto
import eyg/cli/internal/store
import eyg/cli/system
import eyg/hub/cache.{type Cache}
import eyg/hub/client
import eyg/hub/publisher
import eyg/hub/signatory
import eyg/ir/tree as ir
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import midas/continuation.{type Continuation}
import midas/effect
import multiformats/cid/v1
import ogre/operation
import ogre/origin
import untethered/keypair
import untethered/ledger/schema
import untethered/substrate

const max_pull_retries = 3

const pull_retry_delay = 5000

pub type Client {
  Client(origin: origin.Origin)
}

pub fn initialise_principal(keypair, client: Client) {
  let keypair.Keypair(key_id:, ..) = keypair
  let entry = signatory.first(key_id)
  let payload = signatory.to_bytes(entry)
  let signature = crypto.sign(payload, keypair)
  let operation = client.submit_signatory(entry, signature)
  let request = operation.to_request(operation, client.origin)
  use result <- system.then(system.fetch(request))
  case result {
    Ok(response) ->
      client.submit_signatory_response(response)
      |> result.map_error(string.inspect)
    Error(reason) -> Error(effect.describe_fetch_error(reason))
  }
  |> system.Done
}

pub fn pull_principal(client: Client) {
  let operation = client.pull_signatories(schema.pull_parameters())
  let request = operation.to_request(operation, client.origin)
  use result <- system.then(system.fetch(request))
  case result {
    Ok(response) ->
      client.pull_signatories_response(response)
      |> result.map_error(string.inspect)
    Error(reason) -> Error(effect.describe_fetch_error(reason))
  }
  |> system.Done
}

/// Retrieve the complete history for the requested principals from this hub.
pub fn pull_signatories(
  principals: List(v1.Cid),
  client: Client,
) -> system.Effect(Result(List(schema.ArchivedEntry), String)) {
  pull_signatories_page(principals, client, 0, [])
}

fn pull_signatories_page(
  principals: List(v1.Cid),
  client: Client,
  since: Int,
  collected: List(schema.ArchivedEntry),
) {
  let parameters =
    schema.PullParameters(
      entities: list.map(principals, v1.to_string),
      since:,
      limit: 1000,
    )
  let request =
    client.pull_signatories(parameters)
    |> operation.to_request(client.origin)
  use fetched <- system.then(system.fetch(request))
  let response = case fetched {
    Ok(response) ->
      client.pull_signatories_response(response)
      |> result.map_error(string.inspect)
    Error(reason) ->
      Error(effect.describe_fetch_error(reason) |> string.inspect)
  }
  use response <- system.try(response)
  case response.entries {
    [] -> system.Done(Ok(list.reverse(collected)))
    entries -> {
      case
        list.any(entries, fn(entry) {
          entry.cursor <= since || entry.cursor > 9_007_199_254_740_991
        })
      {
        True -> system.Done(Error("invalid or non-advancing signatory cursor"))
        False -> {
          let cursor =
            list.fold(entries, since, fn(cursor, entry) {
              int.max(cursor, entry.cursor)
            })
          let collected =
            list.fold(entries, collected, fn(acc, entry) {
              case list.contains(principals, entry.entity) {
                True -> [entry, ..acc]
                False -> acc
              }
            })
          pull_signatories_page(principals, client, cursor, collected)
        }
      }
    }
  }
}

pub fn share_module(
  source: ir.Node(_),
  client: Client,
) -> system.Effect(Result(v1.Cid, String)) {
  let operation = client.share_module(source)
  let request = operation.to_request(operation, client.origin)
  use result <- system.then(system.fetch(request))
  case result {
    Ok(response) ->
      client.share_response(response) |> result.map_error(string.inspect)
    Error(reason) -> Error(effect.describe_fetch_error(reason))
  }
  |> system.Done
}

pub fn share_bundle(
  bundle: #(#(v1.Cid, BitArray), List(#(v1.Cid, BitArray))),
  client: Client,
) -> system.Effect(Result(v1.Cid, String)) {
  client.share_bundle(bundle, client.origin, fn(request) {
    system.Fetch(request, _)
  })(system.Done)
}

pub fn get_module(
  cid: v1.Cid,
  client: Client,
) -> system.Effect(Result(ir.Node(Nil), String)) {
  client.fetch_module(cid, client.origin, fetch, system.hash)(system.Done)
}

pub fn submit_release(
  signatory: store.Signatory,
  package: String,
  module: v1.Cid,
  previous: Option(#(Int, v1.Cid)),
  client: Client,
) -> system.Effect(Result(schema.ArchivedEntry, String)) {
  let #(sequence, previous) = case previous {
    Some(#(sequence, cid)) -> #(sequence + 1, Some(cid))
    None -> #(1, None)
  }
  let version = sequence
  let store.Signatory(alias: _, principal:, keypair:) = signatory

  let entry =
    substrate.Entry(
      sequence:,
      previous:,
      signatory: principal,
      key: keypair.key_id,
      content: publisher.Release(package:, version:, module:),
    )
  let payload = publisher.to_bytes(entry)
  let signature = crypto.sign(payload, keypair)
  let operation = client.submit_package(entry, signature)
  let request = operation.to_request(operation, client.origin)
  use result <- system.then(system.fetch(request))
  case result {
    Ok(response) ->
      client.submit_package_response(response)
      |> result.map_error(string.inspect)
      |> result.flatten
    Error(reason) -> Error(effect.describe_fetch_error(reason))
  }
  |> system.Done
}

pub fn pull_packages(
  since: Int,
  client: Client,
) -> Promise(Result(List(schema.ArchivedEntry), String)) {
  let parameters = schema.PullParameters(since:, limit: 1000, entities: [])
  client.pull_packages(parameters, client.origin, bun_platform.fetch)(
    promise.resolve,
  )
}

/// Run cache actions until the cache has no more work to do.
/// Failed pulls are retried up to three times, five seconds apart.
pub fn run_all(cache: Cache(Nil)) -> system.Effect(Cache(Nil)) {
  run_all_with(cache, configured_origin(), fetch, system.hash, fn(duration) {
    fn(resume) { system.Wait(duration, resume) }
  })(system.Done)
}

/// Run cache actions with explicit dependencies for deterministic tests.
pub fn run_all_with(
  cache: Cache(Nil),
  origin: origin.Origin,
  fetch: effect.Fetch(t),
  hash: effect.Hash(t),
  wait: fn(Int) -> Continuation(t, Nil),
) -> Continuation(t, Cache(Nil)) {
  run_with_retries(cache, origin, fetch, hash, wait, max_pull_retries)
}

fn run_with_retries(
  cache: Cache(Nil),
  origin: origin.Origin,
  fetch: effect.Fetch(t),
  hash: effect.Hash(t),
  wait: fn(Int) -> Continuation(t, Nil),
  retries: Int,
) -> Continuation(t, Cache(Nil)) {
  use cache <- continuation.then(run_until_idle(cache, origin, fetch, hash))
  case cache.cursor_status {
    cache.PullFailed(_) if retries > 0 -> {
      use _ <- continuation.then(wait(pull_retry_delay))
      run_with_retries(
        cache.pull(cache),
        origin,
        fetch,
        hash,
        wait,
        retries - 1,
      )
    }
    _ -> continuation.return(cache)
  }
}

fn run_until_idle(
  cache: Cache(Nil),
  origin: origin.Origin,
  fetch: effect.Fetch(t),
  hash: effect.Hash(t),
) -> Continuation(t, Cache(Nil)) {
  let #(cache, actions) = cache.flush(cache)
  case actions {
    [] -> continuation.return(cache)
    _ -> {
      use cache <- continuation.then(run_actions(
        actions,
        cache,
        origin,
        fetch,
        hash,
      ))
      run_until_idle(cache, origin, fetch, hash)
    }
  }
}

fn configured_origin() {
  envoy.get("EYG_ORIGIN")
  |> result.try(origin.from_string)
  |> result.unwrap(origin.https("eyg.run"))
}

fn run_actions(
  actions: List(cache.Action),
  cache: Cache(Nil),
  origin: origin.Origin,
  fetch: effect.Fetch(t),
  hash: effect.Hash(t),
) -> Continuation(t, Cache(Nil)) {
  case actions {
    [] -> continuation.return(cache)
    [action, ..rest] -> {
      use completed <- continuation.then(cache.compute(
        action,
        origin,
        fetch,
        hash,
      ))
      let #(cache, _resolved) =
        cache.update(cache, completed, fn(meta) { meta })
      run_actions(rest, cache, origin, fetch, hash)
    }
  }
}

fn fetch(request) {
  system.Fetch(request, _)
}
