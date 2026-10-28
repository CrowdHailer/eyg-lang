//// Model graded checks.
////
//// A judge decides one criterion for one transcript. The prompt follows what
//// works for model graders: a single binary criterion per call, reasoning
//// before the verdict, an explicit way out when the transcript cannot settle
//// the criterion, and no preference for longer answers. The judge can be a
//// different model, from a different family, to the agent under eval.

import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import overlay/eval/agent
import overlay/eval/model.{type Model}
import overlay/eval/render
import overlay/eval/transcript.{type Transcript}
import overlay/llm/chat
import overlay/llm/provider

pub type Decision {
  Meets(reasoning: String)
  DoesNotMeet(reasoning: String)
  CannotTell(reasoning: String)
}

pub const system =
  "You grade transcripts of Overlay, an agent that helps people by writing and running programs in EYG, a scripting language with managed effects.
You decide one criterion at a time and nothing else. Judge only what the transcript shows, never assume work that is not in it.
Longer replies are not better, a short reply that meets the criterion passes."

/// The prompt asking whether a transcript meets a criterion.
pub fn prompt(transcript: Transcript, criterion: String) -> String {
  "<transcript>
" <> render.transcript(transcript) <> "
</transcript>

<criterion>
" <> criterion <> "
</criterion>

Does the transcript meet the criterion?
First reason briefly, quoting the parts of the transcript that decide it.
Then end with a final line that is exactly one of:
VERDICT: PASS
VERDICT: FAIL
VERDICT: UNKNOWN

Use UNKNOWN only when the transcript does not contain enough to decide."
}

/// Read the verdict from the last line that states one.
pub fn decision(text: String) -> Decision {
  let verdict =
    string.split(text, "\n")
    |> list.reverse
    |> list.find_map(fn(line) {
      let line =
        string.uppercase(line)
        |> string.replace("*", "")
        |> string.replace("`", "")
        |> string.trim
      case line {
        "VERDICT: PASS" -> Ok(Meets)
        "VERDICT: FAIL" -> Ok(DoesNotMeet)
        "VERDICT: UNKNOWN" -> Ok(CannotTell)
        _ -> Error(Nil)
      }
    })
  case verdict {
    Ok(verdict) -> verdict(string.trim(text))
    Error(Nil) -> CannotTell("the judge gave no verdict: " <> string.trim(text))
  }
}

/// Ask a judge whether a transcript meets a criterion.
pub fn judge(
  model: Model,
  transcript: Transcript,
  criterion: String,
) -> Promise(Result(Decision, String)) {
  use reply <- promise.map(ask(model, system, prompt(transcript, criterion)))
  case reply {
    Ok(text) -> Ok(decision(text))
    Error(reason) -> Error(reason)
  }
}

/// A single question to a model, without tools.
pub fn ask(
  model: Model,
  system: String,
  question: String,
) -> Promise(Result(String, String)) {
  case model {
    model.Scripted(agent) -> {
      let conversation =
        agent.Conversation(system:, messages: [
          agent.Message(role: "user", content: question, runs: []),
        ])
      promise.resolve(Ok(agent(conversation).text))
    }
    model.Provider(llm:, transport:) -> {
      let request =
        provider.stream_completion_request(
          llm,
          provider.Context(system_prompt: system, tools: []),
          [chat.UserMessage(text: question, images: [])],
        )
      use result <- promise.await(transport(request))
      case result {
        Ok(response) if response.status == 200 ->
          read(llm.provider, response.body, chat.fresh(), <<>>)
        Ok(response) ->
          promise.resolve(Error(
            "the judge returned HTTP " <> string.inspect(response.status),
          ))
        Error(reason) -> promise.resolve(Error(string.inspect(reason)))
      }
    }
  }
}

fn read(source, reader, completion, remaining) {
  use chunk <- promise.await(reader())
  case chunk {
    Ok(Some(bytes)) -> {
      let #(parts, remaining) =
        provider.completion_chunk_parse(source, remaining, bytes)
      read(source, reader, chat.append_chunks(completion, parts), remaining)
    }
    Ok(None) -> promise.resolve(Ok(completion.content))
    Error(reason) -> promise.resolve(Error(string.inspect(reason)))
  }
}
