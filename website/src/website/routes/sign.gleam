import gleam/dynamic/decode
import gleam/javascript/promise
import gleam/list
import gleam/option.{Some}
import lustre
import lustre/attribute as a
import lustre/effect
import lustre/element
import lustre/element/html as h
import mysig/asset
import mysig/html
import plinth/browser/message_event
import plinth/browser/window
import plinth/browser/window_proxy
import website/indexeddb/database
import website/indexeddb/factory
import website/indexeddb/object_store
import website/indexeddb/transaction
import website/routes/common
import website/routes/home
import website/routes/sign/protocol
import website/routes/sign/state
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

const db_name = "KeyStore"

const db_version = 1

const store_name = "keypairs"

pub fn client() {
  let app = lustre.application(do_init, do_update, view.render)
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

fn run(action) {
  case action {
    state.PostMessage(target:, data:) -> post_message(target, data)
    state.ReadKeypairs(database:) -> read_keypairs(database)
  }
}

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

    echo transaction
    let assert Ok(store) = transaction.object_store(transaction, store_name)
    promise.map(object_store.get_all(store), fn(result) { echo result })
    Nil
  })
}
