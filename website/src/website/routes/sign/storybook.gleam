import gleam/option.{None}
import lustre/attribute as a
import lustre/element/html as h
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
          view.render(
            view.model(State(
              opener: None,
              database: state.Fetching,
              keypairs: [],
              mode: state.ViewKeys,
            )),
          ),
        ]),
        card([
          view.render(
            view.model(State(
              opener: None,
              database: state.Fetched(helpers.dummy_db()),
              keypairs: [],
              mode: state.ViewKeys,
            )),
          ),
        ]),
        card([
          view.render(
            view.model(State(
              opener: None,
              database: state.Fetched(helpers.dummy_db()),
              keypairs: [],
              mode: state.SetupKey,
            )),
          ),
        ]),
        card([
          view.render(
            view.model(State(
              opener: None,
              database: state.Fetched(helpers.dummy_db()),
              keypairs: [],
              mode: state.CreatingAccount,
            )),
          ),
        ]),
        card([
          view.render(
            view.model(State(
              opener: None,
              database: state.Fetched(helpers.dummy_db()),
              keypairs: [
                state.Key(
                  id: "abcdefgh",
                  public_key: helpers.dummy_crypto_key(),
                  private_key: helpers.dummy_crypto_key(),
                  entity_id: "foo",
                  entity_nickname: "Personal",
                ),
              ],
              mode: state.ViewKeys,
            )),
          ),
        ]),
      ],
    ),
  ]
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
