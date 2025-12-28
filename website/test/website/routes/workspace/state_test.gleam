import eyg/interpreter/break
import eyg/interpreter/value
import eyg/ir/cid
import eyg/ir/tree as ir
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import morph/analysis
import morph/editable as e
import morph/input
import morph/navigation
import morph/picker
import morph/projection as p
import website/components/snippet
import website/harness/browser
import website/routes/helpers
import website/routes/workspace/state
import website/sync/client
import website/sync/protocol
import website/sync/protocol/server

// contents
// 1. navigation 
// 2. type checked editing
// 3. expression running + effects
// 4. block running + effects + ReadFile
// 5. references
// 6. package lookup
// 7. relative references

// --------------- 1. Navigations -------------------------
pub fn unknown_key_binding_results_in_error_test() {
  let state = no_packages()
  let message = state.UserPressedCommandKey("MagicKey")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert state.user_error == Some(snippet.NoKeyBinding("MagicKey"))

  let message = state.UserPressedCommandKey("e")
  let #(state, _actions) = state.update(state, message)
  // assert actions == []
  assert state.user_error == None
}

pub fn navigate_let_test() {
  let state = no_packages()
  let source = e.Block([#(e.Bind("i"), e.Integer(1))], e.Integer(2), True)
  let p1 = navigation.first(source)
  let state = state.replace_repl(state, p1)

  assert p1
    == #(
      p.Assign(p.AssignPattern(e.Bind("i")), e.Integer(1), [], [], e.Integer(2)),
      [],
    )
  let p2 = #(p.Exp(e.Integer(1)), [
    p.BlockValue(e.Bind("i"), [], [], e.Integer(2)),
  ])
  let p3 = #(p.Exp(e.Integer(2)), [p.BlockTail([#(e.Bind("i"), e.Integer(1))])])

  assert p1 == state.repl.projection

  let message = state.UserPressedCommandKey("ArrowRight")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert p2 == state.repl.projection

  let message = state.UserPressedCommandKey("ArrowRight")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert p3 == state.repl.projection

  let message = state.UserPressedCommandKey("ArrowRight")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert p1 == state.repl.projection

  let message = state.UserPressedCommandKey("ArrowLeft")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert p3 == state.repl.projection

  let message = state.UserPressedCommandKey("ArrowLeft")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert p2 == state.repl.projection

  let message = state.UserPressedCommandKey("ArrowLeft")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert p1 == state.repl.projection
}

pub fn navigate_to_vacant_test() {
  let state = no_packages()
  let source = e.List([e.Integer(1), e.Integer(2), e.Vacant, e.Vacant], None)
  let p1 = navigation.first(source)
  let state = state.replace_repl(state, p1)
  let assert #(p.Exp(e.Integer(1)), _) = state.repl.projection

  let message = state.UserPressedCommandKey(" ")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert #(p.Exp(e.Vacant), [
      p.ListItem(
        pre: [e.Integer(2), e.Integer(1)],
        post: [e.Vacant],
        tail: None,
      ),
    ])
    == state.repl.projection

  let message = state.UserPressedCommandKey(" ")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert #(p.Exp(e.Vacant), [
      p.ListItem(
        pre: [e.Vacant, e.Integer(2), e.Integer(1)],
        post: [],
        tail: None,
      ),
    ])
    == state.repl.projection
}

// --------------- 2. Editing -------------------------

pub const true = e.Call(e.Tag("True"), [e.Record([], None)])

pub const false = e.Call(e.Tag("False"), [e.Record([], None)])

pub fn select_typed_field_test() {
  let state = no_packages()
  let source = e.Record([#("sweet", true), #("size", e.Integer(3))], None)
  let p1 = p.all(source)
  let state = state.replace_repl(state, p1)
  let message = state.UserPressedCommandKey("g")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  let assert state.Picking(picker:, ..) = state.mode
  let assert picker.Typing(value: "", suggestions:) = picker
  assert list.length(suggestions) == 2
  assert Ok("Integer") == list.key_find(suggestions, "size")

  // The picker is weird in that it updates the whole state in the message, and the list of suggestions is constant
  let new = picker.Typing("si", suggestions)
  let message = state.PickerMessage(picker.Updated(new))
  let #(state, actions) = state.update(state, message)
  assert actions == []
  // echo state.mode
  // TODO make sure type checking is done
}

pub fn auto_match_test() {
  let state = no_packages()
  let source = ir.call(ir.builtin("equal"), [ir.integer(1), ir.integer(2)])
  let state = select_all_in_repl(state, source)
  let #(state, actions) = press_key(state, "m")
  assert actions == []
  echo state.mode
  // todo
}

pub fn suggest_shell_effects_test() {
  let state = no_packages()
  let message = state.UserPressedCommandKey("p")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert state.user_error == None
  let assert state.Picking(picker:, ..) = state.mode
  let assert picker.Typing(suggestions:, ..) = picker
  assert list.key_find(suggestions, "Alert") == Ok("String : {}")
}

// --------------- Copy/Paste -------------------------

pub fn can_copy_from_repl_test() {
  let state = no_packages()
  let source = ir.let_("m", ir.string("Top Cat."), ir.variable("m"))
  let state = set_repl(state, source)

  let message = state.UserPressedCommandKey("y")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert state.user_error == Some(snippet.ActionFailed("copy"))

  let message = state.UserPressedCommandKey("ArrowRight")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  let message = state.UserPressedCommandKey("y")
  let #(state, actions) = state.update(state, message)
  let assert [state.WriteToClipboard(text:)] = actions
  assert text == "{\"0\":\"s\",\"v\":\"Top Cat.\"}"
  assert state.user_error == None
  assert state.mode == state.WritingToClipboard

  // return result
  let message = state.ClipboardWriteCompleted(Ok(Nil))
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert state.user_error == None
  assert state.mode == state.Editing

  let message = state.UserPressedCommandKey("a")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert state.user_error == None
  let message = state.UserPressedCommandKey("a")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert state.user_error == None

  let message = state.UserPressedCommandKey("y")
  let #(state, actions) = state.update(state, message)
  let assert [state.WriteToClipboard(text:)] = actions
  assert text
    == "{\"0\":\"l\",\"l\":\"m\",\"t\":{\"0\":\"v\",\"l\":\"m\"},\"v\":{\"0\":\"s\",\"v\":\"Top Cat.\"}}"
  assert state.user_error == None
  assert state.mode == state.WritingToClipboard
}

pub fn can_paste_to_repl_test() {
  let state = no_packages()
  let message = state.UserPressedCommandKey("Y")
  let #(state, actions) = state.update(state, message)
  assert actions == [state.ReadFromClipboard]
  assert state.user_error == None
  assert state.mode == state.ReadingFromClipboard

  let message =
    state.ClipboardReadCompleted(Ok("{\"0\":\"s\",\"v\":\"Wallpaper\"}"))
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert state.user_error == None
  assert state.mode == state.Editing
}

// --------------- 2. Evaluation -------------------------

// New with value
// move prev earlier space to vacant
pub fn evaluation_in_shell_environment_test() {
  let state = no_packages()
  let message = state.UserPressedCommandKey("e")
  let #(state, actions) = state.update(state, message)
  assert actions == [state.FocusOnInput]

  let message = state.PickerMessage(picker.Decided("x"))
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert state.Editing == state.mode
  let assert #(p.Exp(e.Vacant), _) = state.repl.projection

  let message = state.UserPressedCommandKey("n")
  let #(state, actions) = state.update(state, message)
  assert actions == [state.FocusOnInput]

  let message = state.InputMessage(input.UpdateInput("10"))
  let #(state, actions) = state.update(state, message)
  assert actions == []

  let message = state.InputMessage(input.Submit)
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert state.Editing == state.mode

  // There are no variables in scope here
  let message = state.UserPressedCommandKey("v")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  let assert state.Picking(picker:, ..) = state.mode
  assert picker.Typing("", []) == picker
  // let message = state.PickerMessage(picker.Dismissed)
  // let #(state, actions) = state.update(state, message)
  // assert actions == []
  // assert state.Editing == state.mode

  // let message = state.UserPressedCommandKey(" ")
  // let #(state, actions) = state.update(state, message)
  // assert actions == []
  // assert state.Editing == state.mode
  // echo state.repl

  // // let message = state.UserPressedCommandKey("")
  // // let #(state, actions) = state.update(state, message)
  // // assert actions == []
  // // assert state.Editing == state.mode
  // // echo state.repl

  // let message = state.UserPressedCommandKey("v")
  // let #(state, actions) = state.update(state, message)
  // assert actions == [state.FocusOnInput]
  // let assert state.Picking(picker:, ..) = state.mode
  // echo picker
  // assert picker.Typing("", []) == picker
}

// let message = state.PickerMessage(picker.Dismissed)
// let #(state, actions) = state.update(initial, message)

// simple evaluation
// effectful evaluation

pub fn initial_package_sync_test() {
  let #(state, actions) = state.init(helpers.config())
  assert client.syncing(state.sync) == True
  let assert [state.SyncAction(client.SyncFrom(since: 0, ..))] = actions

  let source = ir.integer(100)
  let assert Ok(cid1) = cid.from_tree(source)
  let p1 = protocol.ReleasePublished("foo", 1, cid1)
  let response = server.pull_events_response([p1], 1)

  let message = state.SyncMessage(client.ReleasesFetched(Ok(response)))
  let #(state, actions) = state.update(state, message)
  assert client.syncing(state.sync) == True
  let assert [state.SyncAction(client.FetchFragments(cids:, ..))] = actions
  assert cids == [cid1]

  let response = server.fetch_fragment_response(source)
  let message = state.SyncMessage(client.FragmentFetched(cid1, Ok(response)))
  let #(state, actions) = state.update(state, message)
  assert actions == []

  let message = state.UserPressedCommandKey("@")
  let #(state, actions) = state.update(state, message)
  assert actions == [state.FocusOnInput]
  assert state.ChoosingPackage == state.mode
  assert state.Repl == state.focused

  let assert [release] = state.package_choice(state)
  let assert analysis.Release(package: "foo", version: 1, ..) = release

  let message = state.UserChosePackage(release)
  let #(state, actions) = state.update(state, message)
  assert actions == [state.FocusOnInput]
  assert state.Editing == state.mode
  assert state.Repl == state.focused
  // let message = state.UserPressedCommandKey("Enter")
  // let #(state, actions) = state.update(state, message)
  // assert actions == [state.FocusOnInput]
  // TODO test type and run
}

// test network error fetching packages
// fetch fragment from source
// read the file

// pub fn run_anonymous_reference_test() {
//   let state = no_packages()
//   let message =
//     editor.ShellMessage(
//       shell.CurrentMessage(snippet.UserPressedCommandKey("#")),
//     )
//   let #(state, actions) = editor.update(state, message)
//   assert actions == [editor.FocusOnInput]
//   let assert snippet.Editing(mode) = state.shell.source.status
//   let assert snippet.Pick(picker.Typing(..), ..) = mode

//   let source = ir.unit()
//   let assert Ok(cid) = cid.from_tree(source)

//   let message =
//     editor.ShellMessage(
//       shell.CurrentMessage(snippet.MessageFromPicker(picker.Decided(cid))),
//     )
//   let #(state, actions) = editor.update(state, message)
//   let assert snippet.Editing(snippet.Command) = state.shell.source.status
//   let assert [editor.FocusOnBuffer, editor.SyncAction(action)] = actions
//   let assert client.FetchFragments(cids:, ..) = action
//   assert cids == [cid]
//   // At this point is the snippet fetching what's it's type
// }
// // Reading from scratch is not the same as referencing scratch which must also work

// TODO unknown effect
pub fn unknown_effect_test() {
  let state = no_packages()
  let source = ir.call(ir.perform("Launch"), [ir.string("All the missiles")])
  let source = e.from_annotated(source)
  let p1 = p.all(source)
  let state = state.replace_repl(state, p1)

  let message = state.UserPressedCommandKey("Enter")
  let #(state, actions) = state.update(state, message)

  assert actions == []
  // Should the error be on the shell or a key press error
  let assert state.RunningShell(debug:) = state.mode
  let #(reason, _, _, _) = debug
  let assert break.UnhandledEffect(
    "Launch",
    value.String(value: "All the missiles"),
  ) = reason
}

pub fn bad_input_effect_test() {
  let state = no_packages()

  let source = ir.call(ir.perform("Alert"), [ir.unit()])
  let source = e.from_annotated(source)
  let p1 = p.all(source)
  let state = state.replace_repl(state, p1)

  let message = state.UserPressedCommandKey("Enter")
  let #(state, actions) = state.update(state, message)
  // The ReadFile effect is synchronous in the editor so it concludes.
  assert actions == []
  let assert state.RunningShell(debug:) = state.mode
  let #(reason, _, _, _) = debug
  assert break.IncorrectTerm("String", value.Record(dict.new())) == reason
}

// TODO bad input
pub fn alert_effect_test() {
  let state = no_packages()
  let source = ir.call(ir.perform("Alert"), [ir.string("great test!")])
  let source = e.from_annotated(source)
  let p1 = p.all(source)
  let state = state.replace_repl(state, p1)

  let message = state.UserPressedCommandKey("Enter")
  let #(state, actions) = state.update(state, message)
  // The ReadFile effect is synchronous in the editor so it concludes.
  assert actions == [state.RunEffect(browser.Alert("great test!"))]
  let assert state.RunningShell(..) = state.mode

  // Test multiple effects

  let message = state.EffectImplementationCompleted(123, value.unit())
  let #(state, actions) = state.update(state, message)
  assert actions == []
  let assert state.Editing = state.mode
}

pub fn read_missing_file_test() {
  let state = no_packages()
  let source = ir.call(ir.perform("ReadFile"), [ir.string("index.eyg.json")])
  let source = e.from_annotated(source)
  let p1 = p.all(source)
  let state = state.replace_repl(state, p1)

  let message = state.UserPressedCommandKey("Enter")
  let #(state, actions) = state.update(state, message)
  // The ReadFile effect is synchronous in the editor so it concludes.
  assert actions == []
  // echo state
  // let bytes = dag_json.to_block(ir.vacant())
  // let assert [shell.Executed(value:, effects:, ..)] = state.shell.previous
  // let lowered = value.ok(value.Binary(bytes))
  // assert value == Some(lowered)
  // assert effects == [#("ReadFile", #(value.String("index.eyg.json"), lowered))]
}

pub fn read_source_file_test() {
  let state = no_packages()
  let file = "index.eyg.json"
  let state = state.set_module(state, file, e.Integer(100))

  let source = ir.call(ir.perform("ReadFile"), [ir.string(file)])
  let source = e.from_annotated(source)
  let p1 = p.all(source)
  let state = state.replace_repl(state, p1)

  let message = state.UserPressedCommandKey("Enter")
  let #(state, actions) = state.update(state, message)
  // The ReadFile effect is synchronous in the editor so it concludes.
  assert actions == []
  // echo state
  // let bytes = dag_json.to_block(ir.vacant())
  // let assert [shell.Executed(value:, effects:, ..)] = state.shell.previous
  // let lowered = value.ok(value.Binary(bytes))
  // assert value == Some(lowered)
  // assert effects == [#("ReadFile", #(value.String("index.eyg.json"), lowered))]
}

fn no_packages() {
  let #(state, actions) = state.init(helpers.config())
  let assert [state.SyncAction(client.SyncFrom(since: 0, ..))] = actions
  let response = server.pull_events_response([], 0)
  let message = state.SyncMessage(client.ReleasesFetched(Ok(response)))
  let #(state, actions) = state.update(state, message)
  assert actions == []
  state
}

// Goes to first place in reply
fn set_repl(state, source) {
  let source = e.from_annotated(source)
  let projection = navigation.first(source)
  state.replace_repl(state, projection)
}

fn select_all_in_repl(state, source) {
  let source = e.from_annotated(source)
  let projection = #(p.Exp(source), [])
  state.replace_repl(state, projection)
}

fn press_key(state, key) {
  let message = state.UserPressedCommandKey(key)
  let #(state, actions) = state.update(state, message)
  assert state.user_error == None
  #(state, actions)
}
