import gleam/http/request.{type Request}
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

pub fn completion_request(
  provider,
  model,
  system_prompt,
  history,
  tools,
) -> Request(BitArray) {
  case provider {
    Ollama(config) ->
      ollama.completion_request(config, model, system_prompt, history, tools)
    Mistral(_config) -> panic as "unsupported"
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
