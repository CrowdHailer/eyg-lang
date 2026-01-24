import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import plinth/browser/crypto/subtle
import plinth/browser/indexeddb/database
import plinth/browser/window_proxy
import trust/keypair
import trust/protocol/registry/publisher
import trust/protocol/signatory
import trust/substrate
import website/routes/sign/opener_protocol

pub type State {
  State(
    opener: Option(window_proxy.WindowProxy),
    database: Fetching(database.Database),
    keypairs: List(SignatoryKeypair),
    signatories: List(signatory.Entry),
    mode: Mode,
    error: Option(String),
  )
}

pub type Keypair =
  keypair.Keypair(subtle.CryptoKey, subtle.CryptoKey)

pub type Mode {
  ViewKeys
  SetupDevice
  CreatingSignatory(keypair: Fetching(Keypair))
  ViewSignatory(keypair: SignatoryKeypair)
  SignEntry(entry: Fetching(publisher.Entry))
}

pub type SignatoryKeypair {
  SignatoryKeypair(keypair: Keypair, entity_id: String, entity_nickname: String)
}

pub type Fetching(t) {
  Fetching
  Fetched(t)
  Failed(String)
}

pub type Action {
  // OpenDatabase 
  PostMessage(
    target: window_proxy.WindowProxy,
    data: opener_protocol.OpenerBound,
  )
  ReadKeypairs(database: database.Database)
  CreateKeypair
  CreateSignatory(
    database: database.Database,
    nickname: String,
    keypair: Keypair,
  )
  FetchSignatories(List(String))
}

pub fn init(config) {
  let state =
    State(
      opener: None,
      database: Fetching,
      keypairs: [],
      signatories: [],
      mode: ViewKeys,
      error: None,
    )
  case config {
    Some(opener) -> {
      let action = PostMessage(opener, opener_protocol.GetPayload)
      #(State(..state, mode: SignEntry(Fetching), opener: Some(opener)), [
        action,
      ])
    }
    None -> #(state, [])
  }
}

pub type Message {
  IndexedDBSetup(result: Result(database.Database, String))
  WindowReceivedMessageEvent(
    payload: Result(opener_protocol.PopupBound, List(decode.DecodeError)),
  )
  ReadKeypairsCompleted(result: Result(List(SignatoryKeypair), String))
  UserClickedSetupDevice
  UserClickedCreateSignatory
  UserSubmittedSignatoryAlias(name: String)
  UserClickedAddDeviceToAccount
  UserClickedViewSignatory(key_id: String)
  UserClickedSignPayload
  CreateKeypairCompleted(Result(Keypair, String))
  FetchSignatoriesCompleted(result: Result(List(signatory.Entry), String))
  CreateSignatoryCompleted(
    result: Result(#(signatory.Entry, SignatoryKeypair), String),
  )
}

pub fn update(state, message) {
  case message {
    IndexedDBSetup(result) -> indexeddb_setup(state, result)
    WindowReceivedMessageEvent(payload:) ->
      window_received_message_event(state, payload)
    ReadKeypairsCompleted(result:) -> read_keypairs_completed(state, result)
    UserClickedSetupDevice -> user_clicked_setup_device(state)
    UserClickedCreateSignatory -> user_clicked_create_signatory(state)
    UserSubmittedSignatoryAlias(name:) ->
      user_confirmed_account_creation(state, name)
    UserClickedAddDeviceToAccount -> todo
    UserClickedViewSignatory(key_id:) ->
      user_clicked_view_signatory(state, key_id)
    UserClickedSignPayload -> todo
    CreateKeypairCompleted(result) -> create_keypair_completed(state, result)
    FetchSignatoriesCompleted(result:) ->
      fetch_signatories_completed(state, result)
    CreateSignatoryCompleted(result:) ->
      create_new_signatory_completed(state, result)
  }
}

fn indexeddb_setup(state, result) {
  case result {
    Ok(database) -> {
      let state = State(..state, database: Fetched(database))
      #(state, [ReadKeypairs(database)])
    }
    Error(reason) -> #(State(..state, database: Failed(reason)), [])
  }
}

fn window_received_message_event(state, result) {
  let State(mode:, ..) = state
  case mode {
    SignEntry(Fetching) ->
      case result {
        Ok(opener_protocol.Payload(payload)) -> #(
          State(..state, mode: SignEntry(Fetched(payload))),
          [],
        )
        Error(reason) -> #(
          State(..state, mode: SignEntry(Failed(string.inspect(reason)))),
          [],
        )
      }
    _ -> #(state, [])
  }
}

fn read_keypairs_completed(state, result) {
  case result {
    Ok([]) -> #(State(..state, keypairs: []), [])
    Ok(keypairs) -> {
      let entities = list.map(keypairs, fn(k: SignatoryKeypair) { k.entity_id })
      #(State(..state, keypairs:), [FetchSignatories(entities)])
    }
    Error(_) -> todo
  }
}

fn user_clicked_setup_device(state) {
  let state = State(..state, mode: SetupDevice)
  #(state, [])
}

fn user_clicked_create_signatory(state) {
  let state = State(..state, mode: CreatingSignatory(Fetching))
  #(state, [CreateKeypair])
}

// Don't generate the key async needs GC and saves time only when http also being done
// Is label a better name than name
fn user_confirmed_account_creation(state: State, nickname) {
  let State(mode:, database:, ..) = state
  let assert CreatingSignatory(Fetched(keypair)) = mode
  let assert Fetched(database) = database
  #(state, [CreateSignatory(database:, nickname:, keypair:)])
}

fn user_clicked_view_signatory(state, key_id) {
  let State(keypairs:, ..) = state
  case list.find(keypairs, fn(keypair) { keypair.keypair.key_id == key_id }) {
    Ok(keypair) -> {
      let mode = ViewSignatory(keypair)
      #(State(..state, mode:), [])
    }
    _ -> todo
  }
}

fn create_keypair_completed(state, result) {
  let State(mode:, ..) = state
  case mode {
    CreatingSignatory(Fetching) -> {
      let mode = case result {
        Ok(keypair) -> CreatingSignatory(Fetched(keypair))
        _ -> todo
      }
      #(State(..state, mode:), [])
    }
    _ -> todo
  }
}

fn fetch_signatories_completed(state, result) {
  case result {
    Ok(signatories) -> {
      let state = State(..state, signatories:)
      #(state, [])
    }
    Error(reason) -> todo
  }
}

fn create_new_signatory_completed(state, result) {
  case result {
    Ok(#(entity, keypair)) -> {
      let state =
        State(..state, mode: ViewKeys, keypairs: [keypair, ..state.keypairs])
      #(state, [])
    }
    Error(reason) -> todo
  }
}
