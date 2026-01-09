import gleam/dynamic/decode
import gleam/option.{type Option, None, Some}
import plinth/browser/window_proxy
import website/indexeddb/database
import website/routes/sign/protocol

pub type State {
  State(opener: Option(window_proxy.WindowProxy), keypairs: List(String))
}

pub type Action {
  PostMessage(target: window_proxy.WindowProxy, data: protocol.OpenerBound)
  ReadKeypairs(database: database.Database)
}

pub fn init(config) {
  case config {
    Some(opener) -> {
      let action = PostMessage(opener, protocol.GetPayload)
      #(State(opener: Some(opener), keypairs: []), [action])
    }
    None -> #(State(opener: None, keypairs: []), [])
  }
}

pub type Message {
  IndexedDBSetup(result: Result(database.Database, String))
  WindowReceivedMessageEvent(
    payload: Result(protocol.PopupBound, List(decode.DecodeError)),
  )
  ReadKeypairsCompleted(result: Result(List(String), String))
}

pub fn update(state, message) {
  case message {
    IndexedDBSetup(result) -> indexeddb_setup(state, result)
    WindowReceivedMessageEvent(payload:) -> #(state, [])
    ReadKeypairsCompleted(result:) -> read_keypairs_completed(state, result)
  }
}

fn indexeddb_setup(state, result) {
  case result {
    Ok(database) -> #(state, [ReadKeypairs(database)])
    Error(_) -> todo
  }
}

fn read_keypairs_completed(state, result) {
  case result {
    Ok(keypairs) -> #(State(..state, keypairs:), [])
    Error(_) -> todo
  }
}
