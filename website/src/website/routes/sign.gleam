import gleam/bit_array
import gleam/dynamic/decode
import gleam/dynamicx
import gleam/fetch
import gleam/http
import gleam/javascript/array
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import lustre
import lustre/attribute as a
import lustre/effect
import lustre/element
import lustre/element/html as h
import multiformats/base32
import mysig/asset
import mysig/html
import plinth/browser/crypto
import plinth/browser/crypto/subtle
import plinth/browser/indexeddb/database
import plinth/browser/indexeddb/factory
import plinth/browser/indexeddb/object_store
import plinth/browser/indexeddb/transaction
import plinth/browser/message_event
import plinth/browser/window
import plinth/browser/window_proxy
import spotless/origin
import trust/client as wat
import trust/protocol as trust
import trust/substrate
import website/routes/common
import website/routes/home
import website/routes/sign/protocol
import website/routes/sign/state
import website/routes/sign/storybook
import website/routes/sign/view

pub fn app(module, func) {
  use script <- asset.do(asset.bundle(module, func))
  layout([
    h.div(
      [a.id("app"), a.styles([#("position", "absolute"), #("inset", "0")])],
      [],
    ),
    h.script([a.src(asset.src(script))], ""),
  ])
}

fn layout(body) {
  use layout <- asset.do(asset.load(home.layout_path))
  use neo <- asset.do(asset.load("src/website/routes/neo.css"))
  html.doc(
    list.flatten([
      [
        html.stylesheet(html.tailwind_2_2_11),
        html.stylesheet(asset.src(layout)),
        html.stylesheet(asset.src(neo)),
        common.prism_style(),
        h.style([], "html { height: 100%; }\nbody { min-height: 100%; }\n"),
      ],
      common.page_meta(
        "/",
        "EYG",
        "EYG is a programming language for predictable, useful and most of all confident development.",
      ),
      common.diagnostics(),
    ]),
    body,
  )
  |> asset.done()
}

pub fn page() {
  use content <- asset.do(app("website/routes/sign", "client"))
  asset.done(element.to_document_string(content))
}

pub fn storybook() {
  use content <- asset.do(layout(storybook.render()))
  asset.done(element.to_document_string(content))
}

const db_name = "KeyStore"

const db_version = 1

const store_name = "keypairs"

pub fn client() {
  let app = lustre.application(do_init, do_update, do_render)
  let opener = window.opener(window.self()) |> option.from_result
  let assert Ok(runtime) = lustre.start(app, "#app", opener)
  let assert Ok(indexeddb) = factory.from_window(window.self())
  let p =
    factory.opendb(indexeddb, db_name, db_version, fn(database) {
      let assert Ok(_) =
        database.create_object_store(database, store_name, Some("keyId"), False)
      Nil
    })
  promise.map(p, fn(result) {
    let message = lustre.dispatch(state.IndexedDBSetup(result:))
    lustre.send(runtime, message)
  })
  window.on_message(window.self(), fn(event) {
    let payload =
      decode.run(message_event.data(event), protocol.popup_bound_decoder())

    let message = lustre.dispatch(state.WindowReceivedMessageEvent(payload:))
    lustre.send(runtime, message)
  })
  Nil
}

fn do_init(config) {
  let #(state, actions) = state.init(config)
  #(state, effect.batch(list.map(actions, run)))
}

fn do_update(state, message) {
  let #(state, actions) = state.update(state, message)
  #(state, effect.batch(list.map(actions, run)))
}

fn do_render(state) {
  view.render(state)
}

pub fn run(action) {
  case action {
    state.PostMessage(target:, data:) -> post_message(target, data)
    state.ReadKeypairs(database:) -> read_keypairs(database)
    state.CreateKeypair -> create_keypair()
    state.CreateSignatory(database:, nickname:, keypair:) ->
      create_signatory(database, nickname, keypair)
    state.FetchSignatories(entities) -> fetch_signatories(entities)
  }
}

/// this assumes that the action returns a promise that should be dispatched
fn post_message(target, data) {
  effect.from(fn(_dispatch) {
    let data = protocol.opener_bound_encode(data)
    window_proxy.post_message(target, data, "/")
    Nil
  })
}

fn read_keypairs(database) {
  effect.from(fn(dispatch) {
    let assert Ok(transaction) =
      database.transaction(
        database,
        [store_name],
        database.ReadOnly,
        database.Default,
      )

    let assert Ok(store) = transaction.object_store(transaction, store_name)
    promise.map(object_store.get_all(store), fn(result) {
      let result =
        result.map(result, fn(keys) {
          let keys = array.to_list(keys)
          list.filter_map(keys, fn(key) {
            echo key
            let decoder = {
              use id <- decode.field("keyId", decode.string)
              use public_key <- decode.field("publicKey", crypto_key_decoder())
              use private_key <- decode.field(
                "privateKey",
                crypto_key_decoder(),
              )
              use entity_id <- decode.field("entityId", decode.string)
              use entity_nickname <- decode.field(
                "entityNickname",
                decode.string,
              )
              decode.success(state.SignatoryKeypair(
                state.Keypair(id:, public_key:, private_key:),
                entity_id:,
                entity_nickname:,
              ))
            }
            decode.run(key, decoder) |> echo
          })
        })
      dispatch(state.ReadKeypairsCompleted(result))
    })
    Nil
  })
}

fn create_keypair() {
  effect.from(fn(dispatch) {
    promise.map(do_create_keypair(), fn(result) {
      dispatch(state.CreateKeypairCompleted(result))
    })
    Nil
  })
}

fn do_create_keypair() {
  let usages = [subtle.Sign, subtle.Verify]
  use #(public_key, private_key) <- promise.try_await(subtle.generate_key(
    subtle.Ed25519GenParams,
    False,
    usages,
  ))

  use exported <- promise.try_await(subtle.export(public_key, subtle.Spki))
  let id = base32.encode(exported)
  promise.resolve(Ok(state.Keypair(id:, public_key:, private_key:)))
}

fn crypto_key_decoder() {
  decode.new_primitive_decoder("CryptoKey", fn(x) -> Result(subtle.CryptoKey, _) {
    Ok(dynamicx.unsafe_coerce(x))
  })
}

fn create_signatory(database, nickname, keypair) {
  effect.from(fn(dispatch) {
    promise.map(
      do_create_new_signatory(database, nickname, keypair),
      fn(result) {
        todo
        // dispatch(state.CreateNewSignatoryCompleted(result))
      },
    )
    Nil
  })
}

const origin = origin.Origin(http.Http, "localhost", Some(8001))

// returns a string error
fn do_create_new_signatory(database, nickname, keypair) {
  let endpoint = #(origin, "/id/submit")

  use crypto <- try_sync(
    window.crypto(window.self()) |> result.replace_error("no crypo available"),
  )
  let entity = crypto.random_uuid(crypto)
  let state.Keypair(id: key, public_key:, private_key:) = keypair
  let content = trust.AddKey(key)
  let signatory = substrate.Signatory(entity:, sequence: 0, key:)
  let entry = substrate.first(entity:, signatory:, content:)

  let payload =
    trust.encode(entry)
    |> json.to_string
    |> bit_array.from_string
  use signature <- promise.try_await(subtle.sign(
    subtle.Ed25519,
    private_key,
    payload,
  ))

  let request = wat.submit_request(endpoint, payload, signature)
  use response <- promise.try_await(send_bits(request))
  case response.status {
    200 -> {
      // can't use dynamic properties because it creates a map
      // need a js dynamic object
      let native =
        json.object([
          #("keyId", json.string(key)),
          #("publicKey", dynamicx.unsafe_coerce(dynamicx.from(public_key))),
          #("privateKey", dynamicx.unsafe_coerce(dynamicx.from(private_key))),
          #("entityId", json.string(entity)),
          #("entityNickname", json.string(nickname)),
        ])
      use result <- promise.await(put_keypair(database, dynamicx.from(native)))
      let assert Ok(_) = result
      Ok(#(
        entry,
        state.SignatoryKeypair(
          state.Keypair(id: key, public_key:, private_key:),
          entity_id: entity,
          entity_nickname: nickname,
        ),
      ))
      |> promise.resolve()
    }
    _ ->
      Error("bad response")
      |> promise.resolve()
  }
}

fn fetch_signatories(entities) {
  effect.from(fn(dispatch) {
    promise.map(do_fetch_entities(entities), fn(result) {
      dispatch(state.FetchSignatoriesCompleted(result))
    })
    Nil
  })
}

// returns a string error
fn do_fetch_entities(entities) {
  let endpoint = #(origin, "/id/events")
  echo entities
  // TODO get all the entities
  let assert [entity, ..] = entities

  let request = wat.pull_events_request(endpoint, entity)
  use response <- promise.try_await(send_bits(request))
  use response <- try_sync(
    wat.pull_events_response(response)
    |> result.map_error(string.inspect),
  )

  promise.resolve(Ok(response.events))
}

fn try_sync(result, then) {
  case result {
    Ok(value) -> then(value)
    Error(reason) -> promise.resolve(Error(reason))
  }
}

fn send_bits(request) {
  use response <- promise.await(fetch.send_bits(request))
  use response <- try_sync(result.map_error(response, string.inspect))
  use response <- promise.await(fetch.read_bytes_body(response))
  use response <- try_sync(result.map_error(response, string.inspect))
  promise.resolve(Ok(response))
}

fn put_keypair(database, k) {
  let assert Ok(transaction) =
    database.transaction(
      database,
      [store_name],
      database.ReadWrite,
      database.Strict,
    )
  let assert Ok(store) = transaction.object_store(transaction, store_name)
  object_store.put(store, k, None)
}
