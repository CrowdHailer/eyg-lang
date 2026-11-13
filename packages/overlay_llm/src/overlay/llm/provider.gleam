import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/uri
import midas/continuation.{type Continuation as K}
import midas/effect
import overlay/llm/chat
import overlay/llm/provider/mistral
import overlay/llm/provider/ollama
import overlay/llm/tool

pub type Provider {
  Ollama(ollama.Config)
  Mistral(mistral.Config)
}

pub type Llm {
  Llm(provider: Provider, model: String)
}

/// The context before a conversation starts
/// This is loaded once before a conversation starts
/// Different to agent context that might include skills
/// This is driven by the shape of API's that separate tools from prompt
/// 
/// maybe this is better as chat context
pub type Context {
  Context(system_prompt: String, tools: List(tool.Tool))
}

pub fn completion(
  llm: Llm,
  context: Context,
  history: chat.History,
  fetch: effect.Fetch(t),
) -> K(t, Result(chat.Completion(tool.Call), String)) {
  let request = completion_request(llm, context, history)
  use response <- continuation.map(fetch(request))
  case response {
    Ok(response) -> completion_response(llm, response)
    Error(reason) ->
      Error(
        "request to "
        <> uri.to_string(request.to_uri(request))
        <> " failed: "
        <> effect.describe_fetch_error(reason),
      )
  }
}

pub fn completion_request(
  llm: Llm,
  context: Context,
  history: chat.History,
) -> Request(BitArray) {
  let Llm(provider:, model:) = llm
  let Context(system_prompt:, tools:) = context
  case provider {
    Ollama(config) ->
      ollama.completion_request(config, model, system_prompt, history, tools)
    Mistral(config) ->
      mistral.completion_request(config, model, system_prompt, history, tools)
  }
}

pub fn completion_response(
  llm: Llm,
  response: Response(BitArray),
) -> Result(chat.Completion(tool.Call), String) {
  let Llm(provider:, model: _) = llm
  case provider {
    Ollama(_) -> ollama.completion_response(response)
    Mistral(_) -> mistral.completion_response(response)
  }
}

pub fn stream_completion_request(
  llm: Llm,
  context: Context,
  history: chat.History,
) -> Request(BitArray) {
  let Llm(provider:, model:) = llm
  let Context(system_prompt:, tools:) = context
  case provider {
    Ollama(config) ->
      ollama.stream_completion_request(
        config,
        model,
        system_prompt,
        history,
        tools,
      )

    Mistral(config) ->
      mistral.stream_completion_request(
        config,
        model,
        system_prompt,
        history,
        tools,
      )
  }
}

pub fn completion_chunk_parse(
  provider: Provider,
  remaining: BitArray,
  chunk: BitArray,
) -> #(List(chat.Completion(tool.Call)), BitArray) {
  case provider {
    Ollama(..) -> ollama.completion_chunk_parse(remaining, chunk)
    // Bedrock(..) -> bedrock.completion_chunk_parse(remaining, chunk)
    Mistral(..) -> mistral.completion_chunk_parse(remaining, chunk)
  }
}

/// A short name for the provider, as used by other tools such as opencode.
pub fn id(provider: Provider) -> String {
  case provider {
    Ollama(..) -> "ollama"
    Mistral(..) -> "mistral"
  }
}
