import gleam/dynamic/decode
import gleam/option.{type Option, None, Some}
import plinth/browser/crypto/subtle
import plinth/browser/window_proxy
import website/indexeddb/database
import website/routes/sign/protocol

pub type State {
  State(
    opener: Option(window_proxy.WindowProxy),
    database: Fetching(database.Database),
    keypairs: Fetching(List(Key)),
    mode: Mode,
  )
}

pub type Mode {
  HomePage
  CreatingAccount
}

pub type Key {
  Key(id: String, public: subtle.CryptoKey, private: subtle.CryptoKey)
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
  PostMessage(target: window_proxy.WindowProxy, data: protocol.OpenerBound)
  ReadKeypairs(database: database.Database)
  CreateKey
}

pub fn init(config) {
  let state =
    State(opener: None, database: Fetching, keypairs: Fetching, mode: HomePage)
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
  KeypairCreated(result: Result(#(), String))
}

pub fn update(state, message) {
  case message {
    IndexedDBSetup(result) -> indexeddb_setup(state, result)
    WindowReceivedMessageEvent(payload:) -> #(state, [])
    ReadKeypairsCompleted(result:) -> read_keypairs_completed(state, result)
    UserClickedCreateNewAccount -> user_clicked_create_account(state)
    UserClickedAddDeviceToAccount -> todo
    UserClickedSignPayload -> todo
    KeypairCreated(result:) -> keypair_created(state, result)
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
  #(State(..state, keypairs: fetching_result(result)), [])
}

fn user_clicked_create_account(state) {
  let state = State(..state, mode: CreatingAccount)
  #(state, [CreateKey])
}

fn keypair_created(state, result) {
  case result {
    Ok(keypair) -> {
      todo
    }
    Error(reason) -> todo
  }
}
