import eyg/ir/tree as ir
import gleam/list
import morph/editable as e
import website/components/runner
import website/components/shell
import website/components/snippet
import website/config
import website/harness/harness
import website/sync/client

pub type State {
  State(
    sync: client.Client,
    source: snippet.Snippet,
    shell: shell.Shell(harness.Effect),
    display_help: Bool,
  )
}

pub type Action {
  DoToggleFullScreen
  SyncAction(client.Action)
  // SnippetActions
  // FocusOnBuffer and FocusOnInput relies on autofocus, should be updated to an id managed by parent
  FocusOnBuffer
  FocusOnInput
  // Need to keep record of which thing they refer to
  ReadFromClipboard
  ReadShellFromClipboard
  WriteToClipboad(text: String)
  RunExternalHandler(id: Int, thunk: runner.Thunk(Nil))
}

pub fn init(config) {
  let config.Config(origin:) = config
  let #(client, sync_task) = client.init(origin)
  let actions = list.map(sync_task, SyncAction)
  let shell = shell.init(harness.effects(), client.cache)
  let source = e.from_annotated(ir.vacant())
  let snippet = snippet.init(source)
  let state = State(client, snippet, shell, False)
  #(state, actions)
}

pub type Message {
  ToggleHelp
  ToggleFullscreen
  ShareCurrent
  SnippetMessage(snippet.Message)
  ShellMessage(shell.Message)
  SyncMessage(client.Message)
}

pub fn update(state: State, message) -> #(State, List(Action)) {
  case message {
    ToggleHelp -> #(State(..state, display_help: !state.display_help), [])
    ToggleFullscreen -> #(state, [DoToggleFullScreen])
    ShareCurrent -> {
      let State(sync:, ..) = state
      let editable = snippet.source(state.shell.source)
      let source =
        e.to_annotated(editable, [])
        |> ir.clear_annotation()
      let #(sync, actions) = client.share(sync, source)
      let state = State(..state, sync:)
      // Error action is response possible
      #(state, list.map(actions, SyncAction))
    }
    SnippetMessage(message) -> {
      let #(snippet, action) = snippet.update(state.source, message)
      let State(display_help: display_help, ..) = state

      let #(display_help, snippet_effects) = case action {
        snippet.Nothing -> #(display_help, [])
        snippet.NewCode -> #(display_help, [FocusOnBuffer])
        snippet.Confirm -> #(display_help, [])
        snippet.Failed(_failure) -> #(display_help, [])
        snippet.ReturnToCode -> #(display_help, [FocusOnBuffer])
        snippet.FocusOnInput -> #(display_help, [FocusOnInput])
        snippet.ToggleHelp -> #(!display_help, [])
        snippet.MoveAbove -> #(display_help, [])
        snippet.MoveBelow -> #(display_help, [])
        snippet.ReadFromClipboard -> #(display_help, [])

        snippet.WriteToClipboard(text) -> #(display_help, [
          WriteToClipboad(text:),
        ])
      }
      // let #(cache, tasks) = sync.fetch_all_missing(state.cache)
      // let sync_effect = effect.from(browser.do_sync(tasks, SyncMessage))
      echo "We need the sync effect"
      let state =
        State(
          ..state,
          source: snippet,
          // cache: cache,
          display_help: display_help,
        )
      #(state, snippet_effects)
    }
    ShellMessage(message) -> {
      let #(state, shell_effect) = shell_update(state, message)
      let references =
        snippet.references(state.source)
        |> list.append(snippet.references(state.shell.source))
      // TODO new references from shell message
      let #(sync, actions) = case references {
        [] -> #(state.sync, [])
        _ -> client.fetch_fragments(state.sync, references)
      }
      let actions = list.map(actions, SyncAction)
      let state = State(..state, sync:)

      #(state, list.append(shell_effect, actions))
    }
    SyncMessage(message) -> {
      let State(sync:, ..) = state
      let #(sync, actions) = client.update(sync, message)
      let state = State(..state, sync:)
      let actions = list.map(actions, SyncAction)

      let #(state, shell_action) =
        shell_update(state, shell.CacheUpdate(sync.cache))
      #(state, list.append(shell_action, actions))
    }
  }
}

/// recursivly handle sync effects.
/// Cannot have effects relying on editor state be transformed to thunks when updating editor state
/// For example file write
fn shell_update(state: State, message) {
  let #(shell, shell_effect) = shell.update(state.shell, message)

  let state = State(..state, shell:)
  case shell_effect {
    shell.Nothing -> #(state, [])
    shell.RunExternalHandler(_ref, thunk) -> {
      echo "no effects supported here"
      case thunk {
        // harness.Alert(_message) -> #(state, [
        //   RunExternalHandler(ref, fn() { browser.run(thunk) }),
        // ])
        // browser.ReadFile(file:) -> {
        //   let reply = case file {
        //     "index.eyg.json" -> {
        //       let bytes =
        //         dag_json.to_block(e.to_annotated(state.source.editable, []))
        //       value.ok(value.Binary(bytes))
        //     }
        //     _ -> value.error(value.String("unknown file: " <> file))
        //   }
        //   shell_update(
        //     state,
        //     shell.RunnerMessage(runner.HandlerCompleted(ref, reply)),
        //   )
        // }
        _ -> panic as "need the correct handlers"
      }
    }
    shell.WriteToClipboard(text) -> #(state, [WriteToClipboad(text:)])
    shell.ReadFromClipboard -> #(state, [ReadShellFromClipboard])
    shell.FocusOnCode -> #(state, [FocusOnBuffer])
    shell.FocusOnInput -> #(state, [FocusOnInput])
  }
}
