import gleam/option.{None, Some}
import website/routes/helpers
import website/routes/sign/protocol
import website/routes/sign/state
import website/routes/sign/view

// Test in the workspace that if it's signed then it's signed returns
// state.view(state)
// manage keys if no opener
// Show QR code
// new persona key is only once per 
//
pub fn not_a_popup_test() {
  let #(state, actions) = state.init(None)
  assert [] == actions
  let assert view.Failed(..) = view.model(state)
}

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

  let #(state, actions) = read_keypairs(state, [])
  assert [] == actions
  let assert view.Setup(..) = view.model(state)
  todo
}

fn receive_payload(state, payload) {
  let message = state.WindowReceivedMessageEvent(Ok(protocol.Payload(payload)))
  state.update(state, message)
}

fn database_setup(state, database) {
  let message = state.IndexedDBSetup(Ok(database))
  state.update(state, message)
}

fn read_keypairs(state, keypairs) {
  let message = state.ReadKeypairsCompleted(Ok(keypairs))
  state.update(state, message)
}
