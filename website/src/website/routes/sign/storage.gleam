import gleam/dynamic/decode
import gleam/dynamicx
import gleam/javascript/array
import gleam/javascript/promise.{type Promise}
import gleam/javascript/promisex
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import plinth/browser/crypto/subtle
import plinth/browser/indexeddb/database.{type Database}
import plinth/browser/indexeddb/factory
import plinth/browser/indexeddb/object_store
import plinth/browser/indexeddb/transaction
import untethered/keypair
import website/routes/sign/state

const db_name = "SignatoryKeypairStore"

const db_version = 1

const store_name = "signatoryKeypairs"

const signatory_keypair_index = "keyId"

pub fn start(window) -> Promise(Result(Database, String)) {
  use indexeddb <- promisex.try_sync(
    factory.from_window(window)
    |> result.replace_error("indexeddb unavailable in browser."),
  )

  factory.opendb(indexeddb, db_name, db_version, fn(database) {
    let assert Ok(_) =
      database.create_object_store(
        database,
        store_name,
        Some(signatory_keypair_index),
        False,
      )
    Nil
  })
}

pub fn read_signatories(
  database,
) -> Promise(Result(List(state.SignatoryKeypair), String)) {
  use transaction <- promisex.try_sync(database.transaction(
    database,
    [store_name],
    database.ReadOnly,
    database.Default,
  ))

  use store <- promisex.try_sync(transaction.object_store(
    transaction,
    store_name,
  ))
  promise.map(object_store.get_all(store), fn(result) {
    result.map(result, fn(keys) {
      let keys = array.to_list(keys)
      list.filter_map(keys, fn(key) {
        decode.run(key, signatory_keypair_decoder())
      })
    })
  })
}

fn signatory_keypair_decoder() {
  use key_id <- decode.field("keyId", decode.string)
  use public_key <- decode.field("publicKey", crypto_key_decoder())
  use private_key <- decode.field("privateKey", crypto_key_decoder())
  use entity_id <- decode.field("entityId", decode.string)
  use entity_nickname <- decode.field("entityNickname", decode.string)
  decode.success(state.SignatoryKeypair(
    keypair.Keypair(key_id:, public_key:, private_key:),
    entity_id:,
    entity_nickname:,
  ))
}

fn crypto_key_decoder() {
  decode.new_primitive_decoder("CryptoKey", fn(x) -> Result(subtle.CryptoKey, _) {
    Ok(dynamicx.unsafe_coerce(x))
  })
}

/// This encoder is to JavaScript native values and not JSON.
/// It uses json library and unsafe coercion as no `to_native` or `to_structured_clonable` exists.
fn signatory_keypair_encode(signatory_keypair) {
  let state.SignatoryKeypair(keypair:, entity_id:, entity_nickname:) =
    signatory_keypair
  let keypair.Keypair(key_id:, public_key:, private_key:) = keypair

  json.object([
    #("keyId", json.string(key_id)),
    #("publicKey", dynamicx.unsafe_coerce(dynamicx.from(public_key))),
    #("privateKey", dynamicx.unsafe_coerce(dynamicx.from(private_key))),
    #("entityId", json.string(entity_id)),
    #("entityNickname", json.string(entity_nickname)),
  ])
}

pub fn put_keypair(database, signatory_keypair) {
  let assert Ok(transaction) =
    database.transaction(
      database,
      [store_name],
      database.ReadWrite,
      database.Strict,
    )
  let assert Ok(store) = transaction.object_store(transaction, store_name)
  object_store.put(
    store,
    dynamicx.from(signatory_keypair_encode(signatory_keypair)),
    None,
  )
}
