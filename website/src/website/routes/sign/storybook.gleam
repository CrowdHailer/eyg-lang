import gleam/option.{None}
import lustre/attribute as a
import lustre/element/html as h
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
          )),
        ]),
        card([
          view.render(State(
            opener: None,
            database: state.Fetched(helpers.dummy_db()),
            keypairs: [],
            signatories: [],
            mode: state.ViewKeys,
          )),
        ]),
        card([
          view.render(State(
            opener: None,
            database: state.Fetched(helpers.dummy_db()),
            keypairs: [],
            signatories: [],
            mode: state.SetupDevice,
          )),
        ]),
        card([
          view.render(State(
            opener: None,
            database: state.Fetched(helpers.dummy_db()),
            keypairs: [],
            signatories: [],
            mode: state.CreatingSignatory(state.Fetching),
          )),
        ]),
        card([
          view.render({
            let keypair = generate_keypair("abcdefgh")
            State(
              opener: None,
              database: state.Fetched(helpers.dummy_db()),
              keypairs: [
                state.SignatoryKeypair(
                  keypair:,
                  entity_id: "foo",
                  entity_nickname: "Work",
                ),
                state.SignatoryKeypair(
                  keypair:,
                  entity_id: "bar",
                  entity_nickname: "Personal",
                ),
                state.SignatoryKeypair(
                  keypair:,
                  entity_id: "baz",
                  entity_nickname: "New",
                ),
              ],
              signatories: [
                substrate.Entry(
                  entity: "foo",
                  sequence: 0,
                  previous: None,
                  signatory: substrate.Signatory("abc", 0, ""),
                  content: protocol.AddKey(keypair.id),
                ),
                substrate.Entry(
                  entity: "foo",
                  sequence: 0,
                  previous: None,
                  signatory: substrate.Signatory(keypair.id, 0, ""),
                  content: protocol.RemoveKey(keypair.id),
                ),
                substrate.Entry(
                  entity: "bar",
                  sequence: 0,
                  previous: None,
                  signatory: substrate.Signatory("abc", 0, ""),
                  content: protocol.AddKey(keypair.id),
                ),
              ],
              mode: state.ViewKeys,
            )
          }),
        ]),
        card([
          view.render({
            let keypair = generate_keypair("abcdefgh")
            State(
              opener: None,
              database: state.Fetched(helpers.dummy_db()),
              keypairs: [
                state.SignatoryKeypair(
                  keypair:,
                  entity_id: "id47",
                  entity_nickname: "Personal",
                ),
              ],
              signatories: [
                substrate.Entry(
                  entity: "id47",
                  sequence: 0,
                  previous: None,
                  signatory: substrate.Signatory("abc", 0, ""),
                  content: protocol.AddKey("abc"),
                ),
              ],
              mode: state.ViewSignatory(state.SignatoryKeypair(
                keypair:,
                entity_id: "id47",
                entity_nickname: "Personal",
              )),
            )
          }),
        ]),
      ],
    ),
  ]
}

pub fn generate_keypair(id) {
  let public_key = helpers.dummy_crypto_key()
  let private_key = helpers.dummy_crypto_key()
  state.Keypair(id:, public_key:, private_key:)
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
