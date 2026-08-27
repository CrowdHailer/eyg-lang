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
import gleam/fetchx
import gleam/javascript/promise.{type Promise}
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
  use result <- promise.map(fetchx.send_bits(request))
  case result {
    Ok(response) ->
      client.submit_signatory_response(response)
      |> result.map_error(string.inspect)
    Error(reason) -> Error(string.inspect(reason))
  }
}

pub fn pull_principal(client: Client) {
  let operation = client.pull_signatories(schema.pull_parameters())
  let request = operation.to_request(operation, client.origin)
  use result <- promise.map(fetchx.send_bits(request))
  case result {
    Ok(response) ->
      client.pull_signatories_response(response)
      |> result.map_error(string.inspect)
    Error(reason) -> Error(string.inspect(reason))
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

pub fn get_module(
  cid: v1.Cid,
  client: Client,
) -> Promise(Result(ir.Node(Nil), String)) {
  client.fetch_module(cid, client.origin, bun_platform.fetch)(promise.resolve)
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
  run_all_with(
    cache,
    configured_origin(),
    fn(request) { fn(resume) { system.Fetch(request, resume) } },
    fn(duration) { fn(resume) { system.Wait(duration, resume) } },
  )(system.Done)
}

/// Run cache actions with explicit dependencies for deterministic tests.
pub fn run_all_with(
  cache: Cache(Nil),
  origin: origin.Origin,
  fetch: effect.Fetch(t),
  wait: fn(Int) -> Continuation(t, Nil),
) -> Continuation(t, Cache(Nil)) {
  run_with_retries(cache, origin, fetch, wait, max_pull_retries)
}

fn run_with_retries(
  cache: Cache(Nil),
  origin: origin.Origin,
  fetch: effect.Fetch(t),
  wait: fn(Int) -> Continuation(t, Nil),
  retries: Int,
) -> Continuation(t, Cache(Nil)) {
  use cache <- continuation.then(run_until_idle(cache, origin, fetch))
  case cache.cursor_status {
    cache.PullFailed(_) if retries > 0 -> {
      use _ <- continuation.then(wait(pull_retry_delay))
      run_with_retries(cache.pull(cache), origin, fetch, wait, retries - 1)
    }
    _ -> continuation.return(cache)
  }
}

fn run_until_idle(
  cache: Cache(Nil),
  origin: origin.Origin,
  fetch: effect.Fetch(t),
) -> Continuation(t, Cache(Nil)) {
  let #(cache, actions) = cache.flush(cache)
  case actions {
    [] -> continuation.return(cache)
    _ -> {
      use cache <- continuation.then(run_actions(actions, cache, origin, fetch))
      run_until_idle(cache, origin, fetch)
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
) -> Continuation(t, Cache(Nil)) {
  case actions {
    [] -> continuation.return(cache)
    [action, ..rest] -> {
      use completed <- continuation.then(cache.compute(action, origin, fetch))
      let #(cache, _resolved) =
        cache.update(cache, completed, fn(meta) { meta })
      run_actions(rest, cache, origin, fetch)
    }
  }
}
