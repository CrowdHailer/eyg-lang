import dag_json
import gleam/int
import gleam/option.{None, Some}
import lustre/attribute as a
import lustre/element/html as h
import multiformats/cid/v1
import multiformats/hashes
import trust/keypair
import trust/protocol
import trust/substrate
import website/routes/helpers
import website/routes/sign/state.{State}
import website/routes/sign/view

pub fn render() {
  [
    h.div(
      [
        a.styles([
          #("display", "grid"),
          #("grid-template-columns", "repeat(auto-fill, minmax(400px,500px))"),
          #("gap", "20px"),
          #("justify-content", "center"),
          #("padding", "20px"),
          #("background", "#e3f5ef"),
        ]),
      ],
      [
        // Page has been opened without any payload to sign.
        // 1. Database is loading
        card([
          view.render(State(
            opener: None,
            database: state.Fetching,
            keypairs: [],
            signatories: [],
            mode: state.ViewKeys,
            error: None,
          )),
        ]),
        card([
          view.render(State(
            opener: None,
            database: state.Failed("no db"),
            keypairs: [],
            signatories: [],
            mode: state.ViewKeys,
            error: Some("no db"),
          )),
        ]),
        card([
          view.render(State(
            opener: None,
            database: state.Fetched(helpers.dummy_db()),
            keypairs: [],
            signatories: [],
            mode: state.ViewKeys,
            error: None,
          )),
        ]),
        card([
          view.render(State(
            opener: None,
            database: state.Fetched(helpers.dummy_db()),
            keypairs: [],
            signatories: [],
            mode: state.SetupDevice,
            error: None,
          )),
        ]),
        card([
          view.render(State(
            opener: None,
            database: state.Fetched(helpers.dummy_db()),
            keypairs: [],
            signatories: [],
            mode: state.CreatingSignatory(state.Fetching),
            error: None,
          )),
        ]),
        card([
          view.render({
            let #(work_sig, work_entry) = generate_signatory_keypair("Work")
            let #(personal_sig, personal_entry) =
              generate_signatory_keypair("Personal")
            let #(new_sig, _new_entry) = generate_signatory_keypair("New")

            State(
              opener: None,
              database: state.Fetched(helpers.dummy_db()),
              keypairs: [work_sig, personal_sig, new_sig],
              signatories: [
                work_entry,
                substrate.Entry(
                  // entity: work_sig.entity_id,
                  sequence: 1,
                  previous: Some(v1.Cid(
                    dag_json.code(),
                    hashes.Multihash(hashes.Sha256, <<>>),
                  )),
                  signatory: substrate.Signatory(work_sig.keypair.key_id, 0, ""),
                  content: protocol.RemoveKey(work_sig.keypair.key_id),
                ),
                personal_entry,
              ],
              mode: state.ViewKeys,
              error: None,
            )
          }),
        ]),
        card([
          view.render({
            let #(sig, entry) = generate_signatory_keypair("Personal")
            State(
              opener: None,
              database: state.Fetched(helpers.dummy_db()),
              keypairs: [sig],
              signatories: [entry],
              mode: state.ViewSignatory(sig),
              error: None,
            )
          }),
        ]),
        card([
          view.render({
            let #(sig, entry) = generate_signatory_keypair("Personal")
            State(
              opener: Some(helpers.dummy_opener()),
              database: state.Fetched(helpers.dummy_db()),
              keypairs: [sig],
              signatories: [entry],
              mode: state.SignEntry(state.Fetching),
              error: None,
            )
          }),
        ]),
      ],
    ),
  ]
}

pub fn generate_signatory_keypair(entity_nickname) {
  let keypair = generate_keypair(int.to_string(int.random(100_000)))
  let entity_id = int.to_string(int.random(100_000))
  let signatory_keypair =
    state.SignatoryKeypair(keypair:, entity_id:, entity_nickname:)
  let initial_entry =
    substrate.first(
      entity_id,
      signatory: substrate.Signatory(entity_id, 0, keypair.key_id),
      content: protocol.AddKey(keypair.key_id),
    )
  #(signatory_keypair, initial_entry)
}

pub fn generate_keypair(key_id) {
  let public_key = helpers.dummy_crypto_key()
  let private_key = helpers.dummy_crypto_key()
  keypair.Keypair(key_id:, public_key:, private_key:)
}

fn card(contents) {
  h.div(
    [
      a.styles([
        #("height", "600px"),
        #("background", "#fff"),
      ]),
    ],
    contents,
  )
}
