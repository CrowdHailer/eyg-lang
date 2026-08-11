import gleam/list
import gleam/option.{None, Some}
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event
import overlay/web/provider_setup
import overlay/web/state

pub fn render(model: state.State) {
  let setup = model.provider_setup
  h.div([a.class("provider-settings")], [
    h.button(
      [
        a.class("provider-trigger"),
        a.type_("button"),
        a.disabled(setup.restoring),
        a.title(provider_setup.active_label(setup)),
        event.on_click(message(provider_setup.ToggleSettings)),
      ],
      [
        h.span(
          [a.class("provider-dot configured-" <> bool_class(setup.configured))],
          [],
        ),
        h.span([a.class("provider-label")], [
          h.text(provider_setup.active_label(setup)),
        ]),
      ],
    ),
    case setup.settings_open {
      False -> element.none()
      True -> render_form(model)
    },
  ])
}

fn render_form(model: state.State) {
  let setup = model.provider_setup
  h.form(
    [
      a.class("provider-panel"),
      event.on_submit(fn(_) { message(provider_setup.SaveSettings) }),
    ],
    [
      h.div([a.class("provider-panel-heading")], [
        h.strong([], [h.text("LLM connection")]),
        h.span([], [h.text("Your token stays in this tab.")]),
      ]),
      h.label([], [
        h.span([], [h.text("Provider")]),
        h.select(
          [
            a.name("provider"),
            a.value(provider_value(setup.provider)),
            event.on_change(fn(value) {
              message(provider_setup.ProviderSelected(value))
            }),
          ],
          [
            h.option(
              [a.value(""), a.selected(setup.provider == None)],
              "Choose provider",
            ),
            provider_option(setup.provider, provider_setup.Ollama),
            provider_option(setup.provider, provider_setup.Mistral),
          ],
        ),
      ]),
      h.label([], [
        h.span([], [h.text("Model")]),
        h.select(
          [
            a.name("model"),
            a.value(setup.model_name),
            a.disabled(setup.provider == None),
            event.on_change(fn(value) {
              message(provider_setup.ModelSelected(value))
            }),
          ],
          model_options(setup.provider, setup.model_name),
        ),
      ]),
      h.label([], [
        h.span([], [h.text("API token")]),
        h.input([
          a.name("api-token"),
          a.type_("password"),
          a.value(setup.api_key),
          a.placeholder("Paste token"),
          a.autocomplete("off"),
          event.on_input(fn(value) {
            message(provider_setup.ApiKeyUpdated(value))
          }),
        ]),
      ]),
      case setup.provider {
        Some(selected_provider) ->
          h.a(
            [
              a.class("provider-key-link"),
              a.href(provider_setup.token_url(selected_provider)),
              a.target("_blank"),
            ],
            [
              h.text(
                "Create a "
                <> provider_setup.provider_label(selected_provider)
                <> " API key",
              ),
            ],
          )
        None -> element.none()
      },
      case setup.error {
        Some(error) -> h.p([a.class("provider-error")], [h.text(error)])
        None -> element.none()
      },
      h.button(
        [
          a.class("provider-save"),
          a.type_("submit"),
          a.disabled(!state.can_save_provider(model)),
        ],
        [h.text("Use provider")],
      ),
    ],
  )
}

fn provider_option(selected, provider) {
  h.option(
    [
      a.value(provider_setup.provider_id(provider)),
      a.selected(selected == Some(provider)),
    ],
    provider_setup.provider_label(provider),
  )
}

fn model_options(selected_provider, selected_model) {
  case selected_provider {
    Some(selected_provider) ->
      provider_setup.model_options(selected_provider)
      |> list.map(fn(option) {
        let #(value, label) = option
        h.option([a.value(value), a.selected(value == selected_model)], label)
      })
    None -> [h.option([a.value("")], "Choose provider first")]
  }
}

fn provider_value(selected_provider) {
  case selected_provider {
    Some(selected_provider) -> provider_setup.provider_id(selected_provider)
    None -> ""
  }
}

fn message(message) {
  state.ProviderSetupMessage(message)
}

fn bool_class(value) {
  case value {
    True -> "true"
    False -> "false"
  }
}
