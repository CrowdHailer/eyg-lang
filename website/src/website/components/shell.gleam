import eyg/ir/tree as ir
import gleam/list
import gleam/listx
import gleam/option.{type Option, None, Some}
import morph/editable as e
import plinth/javascript/console
import website/components/readonly
import website/components/snippet
import website/mount/interactive

pub type ShellEntry {
  Executed(
    Option(interactive.Value),
    List(interactive.RuntimeEffect),
    readonly.Readonly,
  )
}

pub type ShellFailure {
  SnippetFailure(snippet.Failure)
  NoMoreHistory
}

pub type Shell {
  Shell(
    failure: Option(ShellFailure),
    previous: List(ShellEntry),
    source: snippet.Snippet,
  )
}

// could just be given a snippet
pub fn init(effects, cache) {
  let source = e.from_annotated(ir.vacant())
  Shell(None, [], snippet.init(source, [], effects, cache))
}

fn close_many_previous(shell_entries) {
  list.map(shell_entries, fn(e) {
    let Executed(a, b, r) = e
    let r = readonly.Readonly(..r, status: readonly.Idle)
    Executed(a, b, r)
  })
}

fn close_all_previous(shell: Shell) {
  let previous = close_many_previous(shell.previous)

  Shell(..shell, previous: previous)
}

pub fn user_clicked_previous(shell: Shell, exp) {
  todo as "where do these live"
  // let scope = shell.source.scope
  // let effects = shell.source.effects
  // let cache = shell.source.cache

  // let current = snippet.active(exp, scope, effects, cache)
  // Shell(..shell, source: current)
}

pub fn shell_snippet_message(shell, message) {
  let shell = close_all_previous(shell)
  let shell = case snippet.user_message(message) {
    True -> Shell(..shell, failure: None)
    False -> shell
  }
  let #(source, eff) = snippet.update(shell.source, message)
  case eff {
    snippet.Nothing -> #(Shell(..shell, source: source), None)
    snippet.Failed(failure) -> #(
      Shell(..shell, failure: Some(SnippetFailure(failure))),
      None,
    )

    // snippet.RunEffect(p) -> #(
    //   Shell(..shell, source: source),
    //   Some(snippet.await_running_effect(p)),
    // )
    snippet.FocusOnCode -> #(Shell(..shell, source: source), {
      snippet.focus_on_buffer()
      None
    })
    snippet.FocusOnInput -> #(Shell(..shell, source: source), {
      snippet.focus_on_input()
      None
    })
    snippet.ToggleHelp -> #(Shell(..shell, source: source), None)
    snippet.MoveAbove -> {
      case shell.previous {
        [] -> #(Shell(..shell, failure: Some(NoMoreHistory)), None)
        [Executed(_value, _effects, readonly), ..] -> {
          todo as "still need a home for these"
          // let scope = shell.source.scope
          // let effects = shell.source.effects
          // let cache = shell.source.cache

          // let current = snippet.active(readonly.source, scope, effects, cache)
          // #(Shell(..shell, source: current), None)
        }
      }
    }
    snippet.MoveBelow -> #(Shell(..shell, source: source), None)
    snippet.ReadFromClipboard -> #(
      Shell(..shell, source: source),
      Some(snippet.read_from_clipboard()),
    )
    snippet.WriteToClipboard(text) -> #(
      Shell(..shell, source: source),
      Some(snippet.write_to_clipboard(text)),
    )
    // snippet.Conclude(value, effects, scope) -> {
    //   let previous = [
    //     Executed(value, effects, readonly.new(snippet.source(shell.source))),
    //     ..shell.previous
    //   ]
    //   let effects = shell.source.effects
    //   let cache = shell.source.cache

    //   let source = snippet.active(e.Vacant, scope, effects, cache)
    //   let shell = Shell(..shell, source: source, previous: previous)
    //   #(shell, None)
    // }
  }
}

pub fn message_from_previous_code(shell: Shell, m, i) {
  let assert Ok(#(pre, executed, post)) = listx.split_around(shell.previous, i)
  let pre = close_many_previous(pre)
  let post = close_many_previous(post)
  let Executed(a, b, r) = executed
  let #(r, action) = readonly.update(r, m)
  let previous = listx.gather_around(pre, Executed(a, b, r), post)
  let effect = case action {
    readonly.Nothing -> None
    readonly.Fail(message) -> {
      console.warn(message)
      None
    }
    readonly.MoveAbove -> None
    readonly.MoveBelow -> None
    readonly.WriteToClipboard(text) -> Some(readonly.write_to_clipboard(text))
  }
  let shell = Shell(..shell, previous: previous)
  #(shell, effect)
}
