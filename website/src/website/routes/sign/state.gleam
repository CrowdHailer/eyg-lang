import gleam/dynamic/decode
import gleam/option.{type Option, None, Some}
import plinth/browser/crypto/subtle
import plinth/browser/indexeddb/database
import plinth/browser/window_proxy
import website/routes/sign/protocol
import website/trust/protocol as trust
import website/trust/substrate

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
  SetupKey
  CreatingAccount
}

pub type Key {
  Key(
    entity_id: String,
    id: String,
    public: subtle.CryptoKey,
    private: subtle.CryptoKey,
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
}

pub fn init(config) {
  let state =
    State(opener: None, database: Fetching, keypairs: [], mode: SetupKey)
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
  UserClickedCreateNewAccount
  UserClickedAddDeviceToAccount
  UserClickedSignPayload
  CreateNewSignatoryCompleted(
    result: Result(substrate.Entry(trust.Event), String),
  )
}

pub fn update(state, message) {
  case message {
    IndexedDBSetup(result) -> indexeddb_setup(state, result)
    WindowReceivedMessageEvent(payload:) -> #(state, [])
    ReadKeypairsCompleted(result:) -> read_keypairs_completed(state, result)
    UserClickedCreateNewAccount -> user_clicked_create_account(state)
    UserClickedAddDeviceToAccount -> todo
    UserClickedSignPayload -> todo
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
  case result {
    Ok(keypairs) -> #(State(..state, keypairs:), [])
    _ -> todo
  }
}

fn user_clicked_create_account(state) {
  let state = State(..state, mode: CreatingAccount)
  let assert Fetched(database) = state.database
  #(state, [CreateNewSignatory(database)])
}

fn create_new_signatory_completed(state, result) {
  case result {
    Ok(keypair) -> {
      todo
    }
    Error(reason) -> todo
  }
}
