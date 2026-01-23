import dag_json
import gleam/option.{None, Some}
import multiformats/cid/v1
import multiformats/hashes
import trust/protocol
import trust/substrate
import website/routes/helpers
import website/routes/sign/state
import website/routes/sign/storybook
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

pub fn failed_to_start_database_test() {
  let #(state, actions) = state.init(None)
  assert [] == actions
  let #(state, actions) =
    state.update(state, state.IndexedDBSetup(Error("oh no DB!")))
  assert [] == actions
  assert state.Failed("oh no DB!") == state.database
}

pub fn fresh_signatory_on_fresh_device_test() {
  let #(state, actions) = initialized([])
  assert [] == actions
  assert state.ViewKeys == state.mode
  let #(state, actions) = state.update(state, state.UserClickedSetupDevice)
  assert [] == actions
  assert state.SetupDevice == state.mode
  let #(state, actions) = state.update(state, state.UserClickedCreateSignatory)
  assert [state.CreateKeypair] == actions
  assert state.CreatingSignatory(state.Fetching) == state.mode

  // TODO try submitting before key generated

  let keypair = storybook.generate_keypair("demo1")
  let #(state, actions) =
    state.update(state, state.CreateKeypairCompleted(Ok(keypair)))
  assert [] == actions
  assert state.CreatingSignatory(state.Fetched(keypair)) == state.mode

  let name = "My first signatory"
  let #(state, actions) =
    state.update(state, state.UserSubmittedSignatoryAlias(name:))
  let assert [state.CreateSignatory(database: _, nickname:, keypair: kp)] =
    actions
  assert name == nickname
  assert kp == keypair
  // I think it would be good to have a new state here with kp removed
  assert state.CreatingSignatory(state.Fetched(keypair)) == state.mode

  let entity_id = "wqhserpbq"
  let event = protocol.AddKey(keypair.id)
  let signatory = substrate.Signatory(entity_id, 0, keypair.id)
  let result =
    Ok(#(
      substrate.first(entity_id, signatory, event),
      state.SignatoryKeypair(keypair:, entity_id:, entity_nickname: name),
    ))
  let #(state, actions) =
    state.update(state, state.CreateSignatoryCompleted(result))
  assert [] == actions
  assert state.ViewKeys == state.mode
  assert [state.SignatoryKeypair(keypair:, entity_id:, entity_nickname: name)]
    == state.keypairs
}

pub fn view_key_test() {
  let keypair = storybook.generate_keypair("old 1")
  let entity_id = "sdvfborf"
  let entity_nickname = "My little signatory"
  let record = state.SignatoryKeypair(keypair:, entity_id:, entity_nickname:)
  let #(state, actions) = initialized([record])
  assert [state.FetchSignatories([entity_id])] == actions
  assert state.ViewKeys == state.mode

  assert [#(record, view.Syncing)] == view.signatories(state)

  let signatory = substrate.Signatory(entity_id, 0, keypair.id)
  let first = substrate.first(entity_id, signatory, protocol.AddKey(keypair.id))
  let result = Ok([first])
  let #(state, actions) =
    state.update(state, state.FetchSignatoriesCompleted(result))
  assert [] == actions
  assert state.ViewKeys == state.mode
  assert [#(record, view.Active)] == view.signatories(state)

  let #(state, actions) =
    state.update(state, state.UserClickedViewSignatory(keypair.id))
  assert [] == actions
  assert state.ViewSignatory(record) == state.mode
}

pub fn view_inactive_key_test() {
  let keypair = storybook.generate_keypair("old 1")
  let entity_id = "sdvfborf"
  let entity_nickname = "My little signatory"
  let record = state.SignatoryKeypair(keypair:, entity_id:, entity_nickname:)
  let #(state, actions) = initialized([record])
  assert [state.FetchSignatories([entity_id])] == actions
  assert state.ViewKeys == state.mode

  let signatory = substrate.Signatory(entity_id, 0, keypair.id)
  let first = substrate.first(entity_id, signatory, protocol.AddKey(keypair.id))
  let second =
    substrate.Entry(
      entity: entity_id,
      sequence: 2,
      previous: Some(v1.Cid(
        dag_json.code(),
        hashes.Multihash(hashes.Sha256, <<>>),
      )),
      signatory: substrate.Signatory(..signatory, sequence: 1),
      content: protocol.RemoveKey(keypair.id),
    )
  let result = Ok([first, second])
  let #(state, actions) =
    state.update(state, state.FetchSignatoriesCompleted(result))
  assert [] == actions
  assert state.ViewKeys == state.mode
  assert [#(record, view.Revoked)] == view.signatories(state)
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

// pub fn sign_with_new_key_test() {
//   let opener = helpers.dummy_opener()
//   let #(state, actions) = state.init(Some(opener))
//   let assert view.Loading(..) = view.model(state)
//   let assert [state.PostMessage(target:, data:)] = actions
//   assert opener == target
//   assert protocol.GetPayload == data

//   let #(state, actions) = receive_payload(state, "hi")
//   assert [] == actions
//   let assert view.Loading(..) = view.model(state)

//   let database = helpers.dummy_db()
//   let #(state, actions) = database_setup(state, database)
//   assert [state.ReadKeypairs(database:)] == actions
//   let assert view.Loading(..) = view.model(state)

//   let #(state, actions) = read_keypairs_completed(state, [])
//   assert [] == actions
//   let assert view.Setup(..) = view.model(state)
//   // let #(state, actions) = create_key_pair(state)
//   // assert [state.CreateKey] == actions
//   // // State should be working again
//   // let message = state.KeypairCreated(Ok(#()))
//   // let #(state, actions) = state.update(state, message)
// }

// sign with already loaded

// fn receive_payload(state, payload) {
//   let message = state.WindowReceivedMessageEvent(Ok(protocol.Payload(payload)))
//   state.update(state, message)
// }

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
