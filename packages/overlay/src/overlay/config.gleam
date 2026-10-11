import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/break
import eyg/interpreter/cast
import eyg/interpreter/state
import eyg/interpreter/value
import gleam/result
import ogre/origin
import overlay/llm/provider
import overlay/llm/provider/mistral
import overlay/llm/provider/ollama
import overlay/policy
import touch_grass/interface

/// Configuration that is common to any overlay agent, chat or otherwise
pub type Config(effect, meta) {
  Config(
    llm: provider.Llm,
    policy: policy.Policy(effect, meta),
    readme: String,
    context: state.Value(meta),
  )
}

pub fn type_(rules, level, bindings) {
  let #(agent_context, bindings) = binding.mono(level, bindings)
  let ollama =
    t.record([
      #("origin", t.String),
      #("api_key", t.option(t.String)),
    ])
  let mistral = t.record([#("api_key", t.String)])
  let llm =
    t.record([
      #(
        "provider",
        t.union([
          #("Ollama", ollama),
          #("Mistral", mistral),
        ]),
      ),
      #("model", t.String),
    ])
  let type_ =
    t.record([
      #("llm", llm),
      #("policy", policy.type_(rules)),
      #("context", agent_context),
    ])
  #(type_, agent_context, bindings)
}

/// Decode configuration using the host's selected effect interfaces and rules.
/// Context remains an EYG value for use by agent programs.
pub fn cast(
  value: state.Value(m),
  rules: List(#(interface.Interface(effect, m), policy.Rule)),
) -> Result(Config(effect, m), state.Reason(m)) {
  case
    cast.field("llm", cast_llm, value),
    cast.field("policy", policy.decode_policy(rules, _), value),
    cast.field("context", cast_context, value)
  {
    Ok(llm), Ok(policy), Ok(#(readme, context)) -> {
      Ok(Config(llm:, policy:, readme:, context:))
    }
    Error(reason), _, _ -> Error(reason)
    Ok(_), Error(reason), _ -> Error(reason)
    Ok(_), Ok(_), Error(reason) -> Error(reason)
  }
}

// cast is the wrong term, we need a decode API
fn cast_llm(value: state.Value(m)) -> Result(provider.Llm, state.Reason(m)) {
  use provider <- result.try(cast.field("provider", cast_provider, value))
  use model <- result.try(cast.field("model", cast.as_string, value))
  Ok(provider.Llm(provider:, model:))
}

fn cast_provider(
  value: state.Value(m),
) -> Result(provider.Provider, state.Reason(m)) {
  use tagged <- result.try(cast.as_tagged(value))
  case tagged {
    #("Ollama", inner) -> result.map(cast_ollama(inner), provider.Ollama)
    #("Mistral", inner) -> result.map(cast_mistral(inner), provider.Mistral)
    #(_, _) -> Error(break.NoMatch(value))
  }
}

fn cast_ollama(
  value: state.Value(m),
) -> Result(ollama.Config, state.Reason(m)) {
  use origin <- result.try(cast.field("origin", cast.as_string, value))
  use origin <- result.try(
    origin.from_string_strict(origin)
    |> result.replace_error(break.IncorrectTerm("origin", value.String(origin))),
  )
  use api_key <- result.try(cast.field(
    "api_key",
    cast.as_option(_, cast.as_string),
    value,
  ))
  Ok(ollama.Config(origin:, api_key:))
}

fn cast_mistral(value) {
  use api_key <- result.try(cast.field("api_key", cast.as_string, value))
  Ok(mistral.Config(api_key:))
}

fn cast_context(value: state.Value(m)) {
  case cast.field("readme", cast.as_string, value) {
    Ok(readme) -> #(readme, value)
    Error(_) -> #("The context has no readme", value)
  }
  |> Ok
}
