import eyg/hub/cache
import eyg/hub/release
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/ir/tree as ir
import eyg/parser
import eyg/parser/debug
import eyg/parser/parser.{type Reason} as _
import gleam/dynamic/decode
import gleam/list
import gleam/string
import midas/continuation.{type Continuation as K}
import oas/generator/utils
import overlay/llm/chat
import overlay/llm/tool
import pal/browser as system
import pal/platform/browser

pub type Context {
  Context(cache: cache.Cache(Meta), counter: Int)
}

// TODO make real meta
pub type Meta =
  List(Int)

pub type Call {
  // The Tool semantics make it not general
  UnknownTool(name: String)
  BadArguments(List(decode.DecodeError))
  InvalidCode(Reason)
  // Needs to be broken up to keep track id
  // Run(Result(state.Value(Meta), state.Debug(Meta)))
  Successful(state.Value(Meta))
  Exception(state.Reason(Meta))
  Aborted(String)
  Handling(task_id: Int, env: state.Env(Meta), k: state.Stack(Meta))
  Pending(dep: cache.Dependency, env: state.Env(Meta), k: state.Stack(Meta))
}

pub type Calls =
  List(#(String, Call))

pub fn execute_all(
  context: Context,
  tool_calls: List(tool.Call),
) -> #(Context, Calls) {
  list.map_fold(tool_calls, context, execute_single)
}

fn execute_single(
  ctx: Context,
  call: tool.Call,
) -> #(Context, #(String, Call)) {
  let tool.Call(id:, function:) = call
  let tool.FunctionCall(name:, arguments:) = function
  case name {
    "run" ->
      case cast_run(arguments) {
        Ok(code) ->
          case parser.all_from_string(code) {
            Ok(source) -> {
              let #(ctx, call) =
                source
                |> ir.map_annotation(fn(_) { [] })
                |> expression.execute([])
                |> loop(ctx)
              #(ctx, #(id, call))
            }
            Error(reason) -> #(ctx, #(id, InvalidCode(reason)))
          }
        Error(reason) -> #(ctx, #(id, BadArguments(reason)))
      }
    _ -> #(ctx, #(id, UnknownTool(name)))
  }
}

fn cast_run(arguments) {
  let arguments = utils.fields_to_dynamic(arguments)
  let decoder = decode.field("code", decode.string, decode.success)
  decode.run(arguments, decoder)
}

// context can include tasks
// If we don't keep track of errors we'll keep calculating
fn loop(
  return: Result(state.Value(Meta), state.Debug(Meta)),
  ctx: Context,
) -> #(Context, Call) {
  case return {
    Error(#(break.UndefinedReference(ref) as break, _m, env, k)) -> {
      case cache.fetch_module(ctx.cache, ref) {
        cache.Ready(cache.Module(value:, type_: _)) ->
          loop(expression.resume(value, env, k), ctx)
        cache.Working(cache) -> {
          let ctx = Context(..ctx, cache:)
          #(ctx, Pending(cache.Content(ref), env, k))
        }
        cache.NotFound(at: _) -> #(ctx, Exception(break))
        cache.Unsound(reason: _) -> #(ctx, Exception(break))
      }
    }
    Error(#(break.UnhandledEffect(label, lift), _, env, k)) -> {
      case browser.cast(label, lift) {
        Ok(effect) -> {
          case browser.e2(effect) {
            Ok(task) ->
              case task(system.Done) {
                system.Done(value) -> loop(Ok(value), ctx)
                _ -> {
                  let t = continuation_map(task, fn(v) { #(1, v) })
                  #(ctx, Handling(1, env, k))
                }
              }

            Error(reason) -> #(ctx, Aborted(reason))
          }
        }
        Error(reason) -> #(ctx, Exception(reason))
      }
    }
    Error(#(reason, _, _, _)) -> #(ctx, Exception(reason))
    Ok(value) -> #(ctx, Successful(value))
  }
}

fn continuation_map(cont: K(t, a), next: fn(a) -> b) -> K(t, b) {
  fn(resume) { cont(fn(a) { continuation.return(next(a))(resume) }) }
}

fn is_running(call: Call) {
  case call {
    UnknownTool(..)
    | BadArguments(..)
    | InvalidCode(..)
    | Successful(..)
    | Exception(..)
    | Aborted(..) -> False
    Handling(..) | Pending(..) -> True
  }
}

pub fn any_running(tool_calls) {
  list.any(tool_calls, fn(tool_call) {
    let #(_, call) = tool_call
    is_running(call)
  })
}

pub fn all_returns(calls) {
  do_all_returns(calls, [])
}

fn do_all_returns(calls: Calls, acc) {
  case calls {
    [] -> Ok(list.reverse(acc))
    [#(id, call), ..calls] -> {
      let message = case call {
        UnknownTool(name:) -> Ok("unknown tool: " <> name)
        BadArguments(reasons) -> Ok(string.inspect(reasons))
        InvalidCode(reason) -> Ok(debug.describe(reason))
        Successful(value) -> Ok(simple_debug.inspect(value))
        Exception(reason) -> Ok(simple_debug.describe(reason))
        Aborted(reason) -> Ok(reason)
        Handling(..) -> Error(Nil)
        Pending(..) -> Error(Nil)
      }
      case message {
        Ok(text) -> {
          let message =
            chat.ToolResultMessage(tool_call_id: id, text:, images: [])
          let acc = [message, ..acc]
          do_all_returns(calls, acc)
        }
        Error(Nil) -> Error(Nil)
      }
    }
  }
}

pub fn restart(
  ctx: Context,
  call: #(String, Call),
) -> #(Context, #(String, Call)) {
  let #(call_id, call) = call
  case call {
    Pending(dep:, env:, k:) -> {
      let reason = cache.dep_to_reason(dep)
      let return = Error(#(reason, [], env, k))
      let #(ctx, call) = loop(return, ctx)
      #(ctx, #(call_id, call))
    }
    _ -> #(ctx, #(call_id, call))
  }
}

pub fn effect_handled(
  ctx: Context,
  calls: List(#(String, Call)),
  id: Int,
  value: state.Value(Meta),
) -> #(Context, List(#(String, Call))) {
  list.map_fold(calls, ctx, fn(ctx, call) { apply_effect(ctx, call, id, value) })
}

fn apply_effect(
  ctx: Context,
  call: #(String, Call),
  finished_id: Int,
  value: state.Value(Meta),
) {
  let #(call_id, call) = call
  case call {
    Handling(task_id:, env:, k:) if task_id == finished_id -> {
      let #(ctx, call) = loop(expression.resume(value, env, k), ctx)
      #(ctx, #(call_id, call))
    }
    _ -> #(ctx, #(call_id, call))
  }
}
