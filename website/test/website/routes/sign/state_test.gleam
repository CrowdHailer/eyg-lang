import gleam/option.{None, Some}
import website/routes/helpers
import website/routes/sign/protocol
import website/routes/sign/state
import website/routes/sign/view

fn initialized(keys) {
  let #(state, actions) = state.init(None)
  // Open database is an assumed effect
  assert [] == actions
  let #(state, actions) = database_setup(state, helpers.dummy_db())
  let assert [state.ReadKeypairs(_)] = actions
  let #(state, actions) = read_keypairs_completed(state, keys)
  #(state, actions)
}

// The wallet keeps the entity id's in the key information
// Keys might not have an entity but if so they are deleted or filtered

pub fn not_a_popup_test() {
  let #(state, actions) = initialized([])
  assert [] == actions
  let #(state, actions) = state.update(state, state.UserClickedCreateNewAccount)
  // stays on the same page
  echo actions
  // let assert view.Loading(..) = view.model(state)
  todo
}

// Test in the workspace that if it's signed then it's signed returns
// state.view(state)
// manage keys if no opener
// Show QR code
// new persona key is only once per 
//

// receive bad payload shows warning
// Lookup keys Ok(List)/Error
// Create new profile or add to an existing profile

pub fn sign_with_new_key_test() {
  let opener = helpers.dummy_opener()
  let #(state, actions) = state.init(Some(opener))
  let assert view.Loading(..) = view.model(state)
  let assert [state.PostMessage(target:, data:)] = actions
  assert opener == target
  assert protocol.GetPayload == data

  let #(state, actions) = receive_payload(state, "hi")
  assert [] == actions
  let assert view.Loading(..) = view.model(state)

  let database = helpers.dummy_db()
  let #(state, actions) = database_setup(state, database)
  assert [state.ReadKeypairs(database:)] == actions
  let assert view.Loading(..) = view.model(state)

  let #(state, actions) = read_keypairs_completed(state, [])
  assert [] == actions
  let assert view.Setup(..) = view.model(state)
  // let #(state, actions) = create_key_pair(state)
  // assert [state.CreateKey] == actions
  // // State should be working again
  // let message = state.KeypairCreated(Ok(#()))
  // let #(state, actions) = state.update(state, message)
}

// sign with already loaded

fn receive_payload(state, payload) {
  let message = state.WindowReceivedMessageEvent(Ok(protocol.Payload(payload)))
  state.update(state, message)
}

fn database_setup(state, database) {
  let message = state.IndexedDBSetup(Ok(database))
  state.update(state, message)
}

fn read_keypairs_completed(state, keypairs) {
  let message = state.ReadKeypairsCompleted(Ok(keypairs))
  state.update(state, message)
}
// fn create_key_pair(state) {
//   let message = state.UserClickedCreateKey
//   state.update(state, message)
// }
