//// One external observation protocol for every service, including the model.
//// Replay is ordered. A fork may reuse an identical prefix, then explicitly
//// switch to live IO; it never searches older observations for a cached reply.

import eyg/interpreter/value as v
import eyg/ir/tree as ir
import glasshouse/bundle
import glasshouse/data
import glasshouse/sha256
import glasshouse/store
import glasshouse/value
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/result
import loam/acquire
import loam/system
import midas/effect
import touch_grass/acquire as acquisition
import touch_grass/http

pub type Exchange {
  Exchange(key: String, reply: Result(Response(BitArray), effect.FetchError))
  Artifact(key: String, receipt: Result(acquire.Receipt, String))
  Refusal(key: String, reason: String)
}

pub type Mode {
  Offline
  Live(hosts: List(String))
  Replay(remaining: List(Exchange))
  Fork(remaining: List(Exchange), hosts: List(String))
}

pub type Broker {
  Broker(
    mode: Mode,
    observations: List(Exchange),
    calls: Int,
    limit: Int,
    sources: List(#(String, Bool)),
  )
}

pub fn new(mode: Mode) -> Broker {
  Broker(mode, [], 0, 1000, [])
}

/// Includes endpoint, method, query, headers and body. Only the fingerprint is
/// retained: credentials are supplied by the caller, not exported in requests.
pub fn key(request: Request(BitArray)) -> String {
  value.fingerprint(http.request_to_eyg(request), sha256.hash)
}

pub fn request(
  broker: Broker,
  request: Request(BitArray),
) -> system.Effect(
  #(Result(Result(Response(BitArray), effect.FetchError), String), Broker),
) {
  let key = key(request)
  use #(observation, broker) <- system.map(
    observe(broker, key, Ok(request.host), fn() {
      use reply <- system.map(system.fetch(request))
      Exchange(key, reply)
    }),
  )
  let reply = case observation {
    Ok(Exchange(_, reply)) -> Ok(reply)
    Ok(_) -> Error("recorded observation is not an HTTP response")
    Error(reason) -> Error(reason)
  }
  #(reply, broker)
}

pub fn acquisition_key(input: acquisition.Input) -> String {
  value.fingerprint(
    v.Tagged("Acquire", acquisition.input_value(input)),
    sha256.hash,
  )
}

pub fn acquire(
  broker: Broker,
  input: acquisition.Input,
  fetcher: acquire.Fetcher,
) -> system.Effect(#(Result(Result(acquire.Receipt, String), String), Broker)) {
  let key = acquisition_key(input)
  use #(observation, broker) <- system.map(
    observe(broker, key, acquire.authority(input.source), fn() {
      use receipt <- system.map(fetcher(input))
      Artifact(key, receipt)
    }),
  )
  let reply = case observation {
    Ok(Artifact(_, receipt)) -> Ok(receipt)
    Ok(_) -> Error("recorded observation is not an acquisition receipt")
    Error(reason) -> Error(reason)
  }
  #(reply, broker)
}

fn observe(
  broker: Broker,
  key: String,
  authority: Result(String, String),
  perform: fn() -> system.Effect(Exchange),
) {
  case broker.calls >= broker.limit {
    True -> refused(broker, key, "external request budget exhausted")
    False ->
      answer(Broker(..broker, calls: broker.calls + 1), key, authority, perform)
  }
}

// The ordering/permission rule is identical for every payload. Adapters and
// codecs know the payload types; this state machine knows only keys/authorities.
fn answer(
  broker: Broker,
  key: String,
  authority: Result(String, String),
  perform: fn() -> system.Effect(Exchange),
) {
  case broker.mode {
    Offline ->
      refused(
        broker,
        key,
        "external request is not available in this environment",
      )
    Replay([exchange, ..rest]) if exchange.key == key ->
      recorded(broker, exchange, Replay(rest))
    Replay(_) -> refused(broker, key, "external observation diverged")
    Fork([exchange, ..rest], hosts) if exchange.key == key ->
      recorded(broker, exchange, Fork(rest, hosts))
    Fork(_, hosts) ->
      answer(Broker(..broker, mode: Live(hosts)), key, authority, perform)
    Live(hosts) ->
      case authority {
        Error(reason) -> refused(broker, key, reason)
        Ok(authority) ->
          case list.contains(hosts, authority) {
            False ->
              refused(
                broker,
                key,
                "external host is not permitted: " <> authority,
              )
            True -> {
              use observation <- system.map(perform())
              #(
                Ok(observation),
                Broker(
                  ..broker,
                  sources: [#(key, False), ..broker.sources],
                  observations: [observation, ..broker.observations],
                ),
              )
            }
          }
      }
  }
}

fn recorded(broker: Broker, exchange: Exchange, mode: Mode) {
  let reply = case exchange {
    Refusal(_, reason) -> Error(reason)
    _ -> Ok(exchange)
  }
  system.Done(#(
    reply,
    Broker(
      ..broker,
      mode:,
      sources: [#(exchange.key, True), ..broker.sources],
      observations: [exchange, ..broker.observations],
    ),
  ))
}

fn refused(broker: Broker, key: String, reason: String) {
  system.Done(#(
    Error(reason),
    Broker(..broker, observations: [Refusal(key, reason), ..broker.observations]),
  ))
}

pub fn finish(broker: Broker) -> Result(Nil, String) {
  case broker.mode {
    Replay([_, ..]) -> Error("external observations remain unconsumed")
    _ -> Ok(Nil)
  }
}

pub fn journal(broker: Broker) -> List(Exchange) {
  list.reverse(broker.observations)
}

pub fn save(broker: Broker, blocks: store.Store) -> #(store.Store, String) {
  let #(blocks, fields) =
    journal(broker)
    |> list.index_fold(#(blocks, []), fn(acc, exchange, index) {
      let #(blocks, fields) = acc
      let #(encoded, blocks) = case exchange {
        Artifact(_, Ok(receipt)) -> {
          let blocks = store.merge(blocks, receipt.artifact.store)
          let payload =
            data.record([
              #(
                "source",
                value.encode(acquisition.source_value(receipt.source)),
              ),
              #("resolved", #(ir.String(receipt.resolved), Nil)),
              #("root", data.link(receipt.artifact.root)),
            ])
          #(#(ir.Apply(#(ir.Tag("Acquired"), Nil), payload), Nil), blocks)
        }
        _ -> {
          let reply = case exchange {
            Artifact(_, Error(reason)) ->
              v.Tagged("AcquisitionError", v.String(reason))
            Artifact(_, Ok(_)) -> panic as "handled above"
            Refusal(_, reason) -> v.Tagged("Refused", v.String(reason))
            Exchange(_, Ok(response)) -> v.ok(http.response_to_eyg(response))
            Exchange(_, Error(effect.NetworkError(reason))) ->
              v.error(v.Tagged("NetworkError", v.String(reason)))
            Exchange(_, Error(effect.UnableToReadBody)) ->
              v.error(v.Tagged("UnableToReadBody", v.unit()))
            Exchange(_, Error(effect.NotImplemented)) ->
              v.error(v.Tagged("NotImplemented", v.unit()))
          }
          let #(encoded, blocks) =
            value.externalize(value.encode(reply), blocks, 512, sha256.hash)
          #(encoded, blocks)
        }
      }
      let node =
        data.record([
          #("key", #(ir.String(exchange.key), Nil)),
          #("reply", encoded),
        ])
      #(blocks, [#(int.to_string(index), node), ..fields])
    })
  store.put_node(blocks, data.record(fields), sha256.hash)
}

pub fn load(
  root: String,
  blocks: store.Store,
) -> Result(List(Exchange), String) {
  use node <- result.try(store.get_node(blocks, root))
  use fields <- result.try(data.fields(node))
  use entries <- result.try(
    list.try_map(fields, fn(field) {
      use index <- result.try(
        int.parse(field.0) |> result.replace_error("invalid observation index"),
      )
      use key <- result.try(data.field(field.1, "key") |> result.try(data.text))
      use encoded <- result.try(data.field(field.1, "reply"))
      use exchange <- result.map(decode_observation(key, encoded, blocks))
      #(index, exchange)
    }),
  )
  Ok(
    entries
    |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
    |> list.map(fn(entry) { entry.1 }),
  )
}

fn decode_observation(key, encoded, blocks) {
  case encoded {
    #(ir.Apply(#(ir.Tag("Acquired"), _), payload), _) -> {
      use source <- result.try(data.field(payload, "source"))
      use source <- result.try(value.decode(source, blocks, Nil))
      use source <- result.try(
        acquisition.decode_source(source)
        |> result.replace_error("invalid acquisition source"),
      )
      use resolved <- result.try(
        data.field(payload, "resolved") |> result.try(data.text),
      )
      use root <- result.try(
        data.field(payload, "root") |> result.try(data.reference),
      )
      use artifact <- result.map(bundle.validate(
        bundle.new(root, blocks),
        sha256.hash,
      ))
      Artifact(key, Ok(acquire.Receipt(source, resolved, artifact)))
    }
    _ -> {
      use reply <- result.try(value.decode(encoded, blocks, Nil))
      case reply {
        v.Tagged("AcquisitionError", v.String(reason)) ->
          Ok(Artifact(key, Error(reason)))
        v.Tagged("Refused", v.String(reason)) -> Ok(Refusal(key, reason))
        v.Tagged("Ok", response) ->
          http.response_to_gleam(response)
          |> result.replace_error("invalid external response")
          |> result.map(fn(response) { Exchange(key, Ok(response)) })
        v.Tagged("Error", v.Tagged("NetworkError", v.String(reason))) ->
          Ok(Exchange(key, Error(effect.NetworkError(reason))))
        v.Tagged("Error", v.Tagged("UnableToReadBody", _)) ->
          Ok(Exchange(key, Error(effect.UnableToReadBody)))
        v.Tagged("Error", v.Tagged("NotImplemented", _)) ->
          Ok(Exchange(key, Error(effect.NotImplemented)))
        _ -> Error("invalid external observation")
      }
    }
  }
}
