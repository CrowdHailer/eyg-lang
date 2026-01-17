import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import plinth/browser/crypto/subtle
import plinth/browser/indexeddb/database
import plinth/browser/window_proxy
import trust/protocol as trust
import trust/substrate
import website/routes/sign/protocol

pub type State {
  State(
    opener: Option(window_proxy.WindowProxy),
    database: Fetching(database.Database),
    // fetching is not the best way to model
    // state and loading mode is better
    keypairs: List(Key),
    mode: Mode,
  )
}

pub type Mode {
  // The SetupKey mode is the home page if no keys
  ViewKeys
  SetupKey
  CreatingAccount
}

pub type Key {
  Key(
    entity_id: String,
    id: String,
    public_key: subtle.CryptoKey,
    private_key: subtle.CryptoKey,
  )
}

pub type Fetching(t) {
  Fetching
  Fetched(t)
  Failed(String)
}

fn fetching_result(result) {
  case result {
    Ok(value) -> Fetched(value)
    Error(reason) -> Failed(reason)
  }
}

pub type Action {
  // OpenDatabase 
  PostMessage(target: window_proxy.WindowProxy, data: protocol.OpenerBound)
  ReadKeypairs(database: database.Database)
  CreateNewSignatory(database: database.Database)
  FetchEntities(List(String))
}

pub fn init(config) {
  let state =
    State(opener: None, database: Fetching, keypairs: [], mode: ViewKeys)
  case config {
    Some(opener) -> {
      let action = PostMessage(opener, protocol.GetPayload)
      #(State(..state, opener: Some(opener)), [action])
    }
    None -> #(state, [])
  }
}

pub type Message {
  IndexedDBSetup(result: Result(database.Database, String))
  WindowReceivedMessageEvent(
    payload: Result(protocol.PopupBound, List(decode.DecodeError)),
  )
  ReadKeypairsCompleted(result: Result(List(Key), String))
  UserClickedSetupDevice
  UserClickedCreateNewAccount
  UserConfirmAccountCreation(name: String)
  UserClickedAddDeviceToAccount
  UserClickedViewAccount
  UserClickedSignPayload
  FetchEntitiesCompleted(
    result: Result(List(substrate.Entry(trust.Event)), String),
  )
  CreateNewSignatoryCompleted(
    result: Result(#(substrate.Entry(trust.Event), Key), String),
  )
}

pub fn update(state, message) {
  case message {
    IndexedDBSetup(result) -> indexeddb_setup(state, result)
    WindowReceivedMessageEvent(payload:) -> #(state, [])
    ReadKeypairsCompleted(result:) -> read_keypairs_completed(state, result)
    UserClickedSetupDevice -> user_clicked_setup_device(state)
    UserClickedCreateNewAccount -> user_clicked_create_account(state)
    UserConfirmAccountCreation(name:) ->
      user_confirmed_account_creation(state, name)
    UserClickedAddDeviceToAccount -> todo
    UserClickedViewAccount -> todo
    UserClickedSignPayload -> todo
    FetchEntitiesCompleted(result:) -> fetch_entities_completed(state, result)
    CreateNewSignatoryCompleted(result:) ->
      create_new_signatory_completed(state, result)
  }
}

fn indexeddb_setup(state, result) {
  case result {
    Ok(database) -> {
      let state = State(..state, database: Fetched(database))
      #(state, [ReadKeypairs(database)])
    }
    Error(_) -> todo
  }
}

fn read_keypairs_completed(state, result) {
  echo result
  case result {
    Ok([]) -> #(State(..state, keypairs: []), [])
    Ok(keypairs) -> {
      let entities = list.map(keypairs, fn(k: Key) { k.entity_id })

      #(State(..state, keypairs:, mode: ViewKeys), [FetchEntities(entities)])
    }
    Error(_) -> todo
  }
}

fn user_clicked_setup_device(state) {
  let state = State(..state, mode: SetupKey)
  let assert Fetched(database) = state.database
  #(state, [])
}

fn user_clicked_create_account(state) {
  let state = State(..state, mode: CreatingAccount)
  let assert Fetched(database) = state.database
  #(state, [])
}

// Don't generate the key async needs GC and saves time only when http also being done
// Is label a better name than name
fn user_confirmed_account_creation(state, name) {
  let state = State(..state, mode: CreatingAccount)
  let assert Fetched(database) = state.database
  #(state, [CreateNewSignatory(database:)])
}

fn fetch_entities_completed(state, result) {
  case result {
    Ok(entries) -> {
      echo entries
      #(state, [])
    }
    Error(reason) -> todo
  }
}

fn create_new_signatory_completed(state, result) {
  case result {
    Ok(#(entity, keypair)) -> {
      echo entity
      let state = State(..state, keypairs: [keypair])
      #(state, [])
    }
    Error(reason) -> todo
  }
}
