import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug as analysis_debug
import eyg/analysis/type_/binding/error
import eyg/hub/cache
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/ir/utils.{push_new} as _
import eyg/parser
import eyg/parser/parser.{type Reason} as _
import glasshouse/journal
import glasshouse/recorder
import gleam/dict
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import multiformats/cid/v1
import overlay/agent
import overlay/llm/chat
import overlay/llm/tool
import overlay/policy
import overlay/tools/run
import overlay/web/trace
import pal/platform/browser
import pal/system
import touch_grass/harness/browser as harness
import touch_grass/interface

pub type Context {
  Context(
    cache: cache.Cache(Meta),
    counter: Int,
    effects: List(system.Effect(#(Int, state.Value(Meta)))),
    context: cache.Module(Meta),
    /// The session so far, effects are recorded into it and the `Trace` effect reads it.
    trace: trace.Trace,
    policy: Option(policy.Policy(harness.Effect, Meta)),
  )
}

pub type Meta =
  List(Int)

/// The running state of a given tool call
pub type Call {
  UnknownTool(name: String)
  BadArguments(List(decode.DecodeError))
  InvalidCode(Reason, String)
  Pulling(ir.Node(Meta))
  Fetching(cids: List(v1.Cid), source: ir.Node(Meta))
  Successful(state.Value(Meta))
  Errored(List(#(Meta, error.Reason)))
  Exception(state.Reason(Meta))
  Aborted(String)
  Handling(
    task_id: Int,
    env: state.Env(Meta),
    k: state.Stack(Meta),
    label: String,
    lift: state.Value(Meta),
    started: Int,
    answer: journal.Answer,
  )
}

/// A tool call state and any output printed.
/// Output and the journal of effects are held most recent first.
pub type Progress {
  Progress(
    id: String,
    output: List(String),
    call: Call,
    code: String,
    program: Option(String),
    journal: List(journal.Entry),
    started: Int,
  )
}

pub type Calls =
  List(Progress)

pub fn execute_all(
  context: Context,
  tool_calls: List(tool.Call),
) -> #(Context, Calls) {
  list.map_fold(tool_calls, context, execute_single)
}

fn execute_single(ctx: Context, call: tool.Call) -> #(Context, Progress) {
  let tool.Call(id:, function:) = call
  let tool.FunctionCall(name:, arguments:) = function
  case agent.cast_tool_call(name, arguments) {
    Ok(agent.Run(code)) -> run_code(ctx, id, code)
    Error(agent.DecodeError(reason)) -> #(ctx, failed(id, BadArguments(reason)))
    Error(agent.UnknownTool) -> #(ctx, failed(id, UnknownTool(name)))
  }
}

fn run_code(ctx: Context, id: String, code: String) -> #(Context, Progress) {
  let pending = waiting(id, code)
  case parser.all_from_string(code) {
    Ok(source) -> {
      let source = ir.map_annotation(source, fn(_) { [] })
      case check_single(source, ctx.cache, ctx.context) {
        [] -> start(ctx, pending, source)
        errors -> {
          let references = missing_references(errors)
          case requires_pull(references, ctx.cache) {
            True -> {
              let cache = cache.pull(ctx.cache)
              let ctx = Context(..ctx, cache:)
              #(ctx, Progress(..pending, call: Pulling(source)))
            }
            False -> {
              case to_fetch(references, ctx.cache, []) {
                [] -> #(ctx, Progress(..pending, call: Errored(errors)))
                needed -> {
                  let cache = cache.fetch_all(ctx.cache, needed)
                  let ctx = Context(..ctx, cache:)
                  #(ctx, Progress(..pending, call: Fetching(needed, source)))
                }
              }
            }
          }
        }
      }
    }
    Error(reason) -> #(
      ctx,
      Progress(..pending, call: InvalidCode(reason, code)),
    )
  }
}

fn waiting(id, code) {
  Progress(
    id:,
    output: [],
    call: Aborted("not started"),
    code:,
    program: None,
    journal: [],
    started: trace.now(),
  )
}

// Pin the program, every reference is in the cache once it type checks, then run it.
fn start(ctx: Context, progress: Progress, source) -> #(Context, Progress) {
  let #(recorded, program) = trace.pin(ctx.trace, source, ctx.cache)
  let ctx = Context(..ctx, trace: recorded)
  let progress =
    Progress(..progress, program: Some(program), started: trace.now())
  source
  |> execute(ctx.context)
  |> loop(ctx, progress)
}

/// The effects a tool program can use, the browser's and `Trace`.
pub fn effects() {
  let services =
    list.map(
      [harness.DNSimple, harness.GitHub, harness.Vimeo],
      harness.effect_label,
    )
  let effects =
    harness.effects()
    |> list.filter(fn(effect) { !list.contains(services, effect.name) })
  list.append(effects, [trace.interface()])
}

fn check_single(
  source: #(ir.Expression(a), a),
  cache: cache.Cache(b),
  context: cache.Module(_),
) -> List(#(a, error.Reason)) {
  let analysis =
    infer.pure()
    |> with_scope([#("context", context.type_)])
    |> infer.with_effects(interface.types(effects()))
    |> infer.check(source)
    |> cache.infer_sync(cache)
  infer.all_errors(analysis)
}

// TODO move to infer module
fn with_scope(
  context: infer.Context,
  scope: List(#(String, binding.Poly)),
) -> infer.Context {
  let infer.Context(env:, ..) = context
  infer.Context(..context, env: list.append(scope, env))
}

pub fn missing_references(errors) {
  list.filter_map(errors, fn(error) {
    let #(_, error) = error
    case error {
      error.MissingReference(reference:) -> Ok(reference)
      _ -> Error(Nil)
    }
  })
}

fn requires_pull(refs, cache) {
  case refs {
    [] -> False
    [reference, ..rest] ->
      case reference {
        ir.Content(..) | ir.Relative(..) -> requires_pull(rest, cache)
        ir.Package(package:) ->
          case cache.package(cache, package) {
            Ok(_) -> requires_pull(rest, cache)
            Error(_) -> True
          }
        ir.Version(package:, version:) ->
          case cache.unbound_release(cache, package, version) {
            Ok(_) -> requires_pull(rest, cache)
            Error(_) -> True
          }
        ir.Pinned(release: ir.Release(package:, version:, module: _)) ->
          case cache.unbound_release(cache, package, version) {
            Ok(_) -> requires_pull(rest, cache)
            Error(_) -> True
          }
      }
  }
}

pub fn to_fetch(
  refs: List(ir.Reference),
  cache: cache.Cache(a),
  acc: List(v1.Cid),
) -> List(v1.Cid) {
  case refs {
    [] -> acc
    [reference, ..rest] -> {
      let acc = case reference {
        ir.Content(cid:) -> push_new(acc, cid)
        ir.Package(package:) ->
          case cache.package(cache, package) {
            Ok(cache.Entry(module:, ..)) -> push_new(acc, module)
            Error(_) -> acc
          }
        ir.Version(package:, version:) ->
          case cache.unbound_release(cache, package, version) {
            Ok(cid) -> push_new(acc, cid)
            Error(_) -> acc
          }
        // Only the release log can make a pin right, so there is nothing to
        // gain from fetching a module it does not name for that release.
        ir.Pinned(release: ir.Release(package:, version:, module:)) ->
          case cache.unbound_release(cache, package, version) {
            Ok(cid) if cid == module -> push_new(acc, module)
            _ -> acc
          }
        ir.Relative(..) -> acc
      }
      to_fetch(rest, cache, acc)
    }
  }
}

fn failed(id, call) {
  Progress(..waiting(id, ""), call:)
}

// context can include tasks
// If we don't keep track of errors we'll keep calculating
// prepare and fetch all need to look at relative references
// Or we just type check and lookup
// There's multiple ways to do this, pick one.
// 1. reset failed
// 2. reset pulled
// document/state

fn loop(
  return: Result(state.Value(Meta), state.Debug(Meta)),
  ctx: Context,
  progress: Progress,
) -> #(Context, Progress) {
  let finish = fn(ctx, progress, call) { #(ctx, Progress(..progress, call:)) }
  case return {
    Error(#(break.UndefinedReference(reference) as break, _m, env, k)) -> {
      case reference {
        ir.Relative(location:) -> {
          let message = "unable to load source from location: " <> location
          finish(ctx, progress, Aborted(message))
        }
        _ ->
          case cache.get_reference(ctx.cache, reference) {
            Ok(cache.Module(value:, ..)) ->
              loop(expression.resume(value, env, k), ctx, progress)
            Error(Nil) -> finish(ctx, progress, Exception(break))
          }
      }
    }
    // The session so far, answered without leaving the page.
    Error(#(break.UnhandledEffect("Trace", lift), _, env, k)) -> {
      let reply = trace.reply(ctx.trace)
      let #(ctx, progress) =
        record(ctx, progress, "Trace", lift, reply, trace.now())
      loop(expression.resume(reply, env, k), ctx, progress)
    }
    Error(#(break.UnhandledEffect(label, lift), _, env, k)) -> {
      case decide(ctx, label, lift) {
        Perform(sent) -> {
          let answer = case ctx.policy, sent == lift {
            None, _ -> journal.Performed
            Some(_), True -> journal.Gated
            Some(_), False ->
              journal.Altered(recorder.fingerprint(ctx.trace.recorder, sent))
          }
          perform(label, lift, sent, answer, env, k, ctx, progress)
        }
        Resume(reply) -> {
          let #(ctx, progress) =
            record_answer(
              ctx,
              progress,
              label,
              lift,
              reply,
              journal.Mocked,
              trace.now(),
            )
          loop(expression.resume(reply, env, k), ctx, progress)
        }
        Refuse(reason) -> finish(ctx, progress, Aborted(reason))
      }
    }
    Error(#(reason, _, _, _)) -> finish(ctx, progress, Exception(reason))
    Ok(value) -> finish(ctx, progress, Successful(value))
  }
}

fn finish(ctx, progress, call) {
  #(ctx, Progress(..progress, call:))
}

fn perform(
  label,
  lift,
  sent,
  answer,
  env,
  k,
  ctx: Context,
  progress: Progress,
) {
  let started = trace.now()
  case browser.cast(label, sent) {
    // Printing belongs to the result the agent reads, not only the browser
    // console. Keeping it here also preserves output across suspension.
    Ok(harness.Print(message)) -> {
      let #(ctx, progress) =
        record_answer(ctx, progress, label, lift, v.unit(), answer, started)
      let progress = Progress(..progress, output: [message, ..progress.output])
      loop(expression.resume(v.unit(), env, k), ctx, progress)
    }
    Ok(effect) -> {
      case browser.extrinsic(effect) {
        browser.Abort(reason) -> finish(ctx, progress, Aborted(reason))
        browser.Work(system.Done(value)) -> {
          let #(ctx, progress) =
            record_answer(ctx, progress, label, lift, value, answer, started)
          loop(expression.resume(value, env, k), ctx, progress)
        }
        browser.Work(effect) -> {
          let id = ctx.counter

          let effect = system.map(effect, fn(v) { #(id, v) })
          let effects = [effect, ..ctx.effects]
          let ctx = Context(..ctx, counter: id + 1, effects:)
          finish(
            ctx,
            progress,
            Handling(id, env, k, label, lift, started, answer),
          )
        }
        browser.Spotless(..) ->
          finish(
            ctx,
            progress,
            Aborted("Spotless integration not supported in harness"),
          )
      }
    }
    Error(reason) -> finish(ctx, progress, Exception(reason))
  }
}

fn record(ctx: Context, progress: Progress, label, lift, reply, started) {
  record_answer(ctx, progress, label, lift, reply, journal.Performed, started)
}

fn record_answer(
  ctx: Context,
  progress: Progress,
  label,
  lift,
  reply,
  answer,
  started,
) {
  let #(recorded, entry) =
    trace.answer(ctx.trace, label, lift, reply, answer, started, trace.now())
  #(
    Context(..ctx, trace: recorded),
    Progress(..progress, journal: [entry, ..progress.journal]),
  )
}

fn is_running(call: Call) {
  case call {
    UnknownTool(..)
    | BadArguments(..)
    | InvalidCode(..)
    | Successful(..)
    | Errored(..)
    | Exception(..)
    | Aborted(..) -> False
    Handling(..) | Pulling(..) | Fetching(..) -> True
  }
}

pub fn any_running(tool_calls: Calls) {
  list.any(tool_calls, fn(progress: Progress) { is_running(progress.call) })
}

pub fn all_returns(calls) {
  do_all_returns(calls, [])
}

fn do_all_returns(
  calls: Calls,
  acc: List(chat.Message(a)),
) -> Result(List(chat.Message(a)), Nil) {
  case calls {
    [] -> Ok(list.reverse(acc))
    [Progress(id:, output:, call:, ..), ..calls] -> {
      let message = case call {
        UnknownTool(name:) -> Ok("unknown tool: " <> name)
        BadArguments(reasons) -> Ok(string.inspect(reasons))
        InvalidCode(reason, code) -> Ok(parser.format_error(reason, code))
        Successful(value) -> Ok(agent.inspect_result(value))
        Errored(errors) -> {
          list.map(errors, fn(error) { analysis_debug.reason(error.1) })
          |> string.join("\n")
          |> Ok()
        }
        Exception(reason) -> Ok(simple_debug.describe(reason))
        Aborted(reason) -> Ok(reason)
        Handling(..) | Pulling(..) | Fetching(..) -> Error(Nil)
      }
      case message {
        Ok(text) -> {
          let message =
            chat.ToolResultMessage(
              tool_call_id: id,
              text: agent.tool_result_text(run.report(output, text)),
              images: [],
            )
          do_all_returns(calls, [message, ..acc])
        }
        Error(Nil) -> Error(Nil)
      }
    }
  }
}

pub fn pulled(ctx: Context, progress: Progress) -> #(Context, Progress) {
  case progress.call {
    Pulling(source) -> {
      // TODO move to cache.infer_sync that will gather need to pull and to fetch references
      case check_single(source, ctx.cache, ctx.context) {
        [] -> start(ctx, progress, source)
        errors -> {
          // Don't check for needs pull here as we've aready done that.
          let references = missing_references(errors)
          case to_fetch(references, ctx.cache, []) {
            [] -> #(ctx, Progress(..progress, call: Errored(errors)))
            needed -> {
              let cache = cache.fetch_all(ctx.cache, needed)
              let ctx = Context(..ctx, cache:)
              #(ctx, Progress(..progress, call: Fetching(needed, source)))
            }
          }
        }
      }
    }
    _ -> #(ctx, progress)
  }
}

fn execute(source: ir.Node(Meta), context: cache.Module(Meta)) {
  expression.execute(source, [#("context", context.value)])
}

pub fn check_fetching(
  ctx: Context,
  progress: Progress,
) -> #(Context, Progress) {
  case progress.call {
    Fetching(cids:, source:) -> {
      let cids = list.filter(cids, still_fetching(_, ctx.cache))
      case cids {
        [] ->
          case check_single(source, ctx.cache, ctx.context) {
            [] -> start(ctx, progress, source)
            errors -> #(ctx, Progress(..progress, call: Errored(errors)))
          }
        _ -> #(ctx, Progress(..progress, call: Fetching(cids, source)))
      }
    }
    _ -> #(ctx, progress)
  }
}

// TODO move this to cache
pub fn still_fetching(cid, cache) {
  case cache.get_module(cache, cid) {
    Ok(_) -> False
    // Not requested is the state given by fetch and before flush.
    // It means not requested from the network not never requested by the user.
    Error(cache.NotRequested)
    | Error(cache.Requested(..))
    | Error(cache.DependsOn(..)) -> True

    Error(cache.Failed(_)) | Error(cache.Invalid(_)) -> False
  }
}

pub fn effect_handled(
  ctx: Context,
  calls: Calls,
  id: Int,
  value: state.Value(Meta),
) -> #(Context, Calls) {
  list.map_fold(calls, ctx, fn(ctx, call) { apply_effect(ctx, call, id, value) })
}

fn apply_effect(
  ctx: Context,
  progress: Progress,
  finished_id: Int,
  value: state.Value(Meta),
) {
  case progress.call {
    Handling(task_id:, env:, k:, label:, lift:, started:, answer:)
      if task_id == finished_id
    -> {
      let #(ctx, progress) =
        record_answer(ctx, progress, label, lift, value, answer, started)
      loop(expression.resume(value, env, k), ctx, progress)
    }
    _ -> #(ctx, progress)
  }
}

type Outcome {
  Perform(state.Value(Meta))
  Resume(state.Value(Meta))
  Refuse(String)
}

/// The rules for a policy entered in the browser.
/// Effects that do no IO, and aborting, need no gate.
pub fn policy_rules() {
  policy.match_rules(effects(), [
    #("Abort", policy.Unchecked),
    #("Alert", policy.PolicyField("alert")),
    #("Copy", policy.PolicyField("copy")),
    #("DecodeJSON", policy.Unchecked),
    #("Download", policy.PolicyField("download")),
    #("Fetch", policy.PolicyField("fetch")),
    #("Flip", policy.Unchecked),
    #("Now", policy.PolicyField("now")),
    #("Paste", policy.PolicyField("paste")),
    #("Print", policy.PolicyField("print")),
    #("Prompt", policy.PolicyField("prompt")),
    #("Random", policy.Unchecked),
    #("Trace", policy.Unchecked),
    #("Visit", policy.PolicyField("visit")),
  ])
}

/// Ask the policy, if there is one, what to do with an effect.
fn decide(ctx: Context, label, lift) -> Outcome {
  case ctx.policy {
    None -> Perform(lift)
    Some(policy) ->
      case dict.get(policy, label) {
        Ok(policy.Interface(_, policy.Gated(gate))) -> {
          let return =
            expression.call(gate, [#(lift, [])])
            |> cache.static_loop(ctx.cache, expression.resume)
          case return {
            Ok(returned) ->
              case policy.decision_from_value(returned) {
                Ok(policy.Pass(lift)) -> Perform(lift)
                Ok(policy.Mock(value)) -> Resume(value)
                Error(Nil) ->
                  Refuse(
                    "policy for "
                    <> label
                    <> " failed: expected Pass or Mock, got "
                    <> simple_debug.inspect(returned),
                  )
              }
            Error(#(reason, _, _, _)) ->
              Refuse(
                "policy for "
                <> label
                <> " failed: "
                <> simple_debug.describe(reason),
              )
          }
        }
        Ok(policy.Interface(_, policy.Unrestricted)) -> Perform(lift)
        Error(Nil) -> Refuse("the " <> label <> " effect is not available")
      }
  }
}
