import cloud/server
import cloud/stream
import gleam/erlang/process
import gleam/http
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import ogre/origin
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/provider/ollama

fn shown(subject, acc) {
  case process.receive(subject, 0) {
    Ok(text) -> shown(subject, [text, ..acc])
    Error(Nil) -> list.reverse(acc)
  }
}

pub fn show_text_as_it_arrives_test() {
  let server = server.start(process.new_subject())
  let texts = process.new_subject()
  let history = [chat.UserMessage("slow: a longer message", [])]
  let assert Ok(completion) =
    stream.complete(
      server.llm(server),
      provider.Context("", []),
      history,
      fn(completion) { process.send(texts, completion.content) },
    )
  assert completion.content == "slow: a longer message #1"
  // The text grows as it arrives and ends as the completion.
  let shown = shown(texts, [])
  assert list.length(shown) > 1
  let assert Ok(last) = list.last(shown)
  assert last == completion.content
  let assert [first, ..] = shown
  assert string.starts_with(completion.content, first)
  assert first != completion.content
}

pub fn tool_calls_are_streamed_test() {
  let server = server.start(process.new_subject())
  let history = [chat.UserMessage("run:1", [])]
  let assert Ok(chat.Completion(tool_calls: [_], ..)) =
    stream.complete(
      server.llm(server),
      provider.Context("", []),
      history,
      fn(_) { Nil },
    )
}

pub fn failed_request_test() {
  // Nothing listens on port 1.
  let origin = origin.Origin(http.Http, "localhost", Some(1))
  let llm = provider.Llm(provider.Ollama(ollama.Config(origin, None)), "test")
  let assert Error(_) =
    stream.complete(llm, provider.Context("", []), [], fn(_) { Nil })
}

pub fn thinking_is_streamed_test() {
  let server = server.start(process.new_subject())
  let arrived = process.new_subject()
  let history = [chat.UserMessage("think:hard", [])]
  let assert Ok(completion) =
    stream.complete(
      server.llm(server),
      provider.Context("", []),
      history,
      process.send(arrived, _),
    )
  assert completion.thinking == "Thinking about think:hard #1"
  assert completion.content == "think:hard #1"
  // The thinking arrives before the text.
  let assert [first, ..] = shown(arrived, [])
  assert first.content == "" && first.thinking != ""
}
