import eyg/interpreter/break
import eyg/interpreter/value
import eyg/ir/cid
import eyg/ir/tree as ir
import gleam/dict
import gleam/int
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
  let source = ir.let_("i", ir.integer(1), ir.integer(2))
  let state = set_repl(state, source)

  let p1 = #(
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
  let source = ir.list([ir.integer(1), ir.integer(2), ir.vacant(), ir.vacant()])
  let state = set_repl(state, source)

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

// TODO create Module
// Open Module
// Escape is back
pub fn vertical_move_in_file_test() {
  let state = no_packages()
  let state =
    set_module(state, "foo.eyg.json", ir.let_("x", ir.string("a"), ir.unit()))
  let state = state.State(..state, focused: state.Module("foo.eyg.json"))
  let reason = press_key_failure(state, "ArrowUp")
  assert snippet.ActionFailed("move above") == reason

  let #(state, actions) = press_key(state, "ArrowDown")
  assert [] == actions
  let module = read_module(state, "foo.eyg.json")
  let assert #(p.Exp(e.Record([], None)), [p.BlockTail(..)]) = module.projection

  let reason = press_key_failure(state, "ArrowDown")
  assert snippet.ActionFailed("move below") == reason
}

// --------------- 2. Editing -------------------------

pub const true = e.Call(e.Tag("True"), [e.Record([], None)])

pub const false = e.Call(e.Tag("False"), [e.Record([], None)])

pub fn select_typed_field_test() {
  let state = no_packages()
  let source = ir.record([#("sweet", ir.true()), #("size", ir.integer(3))])
  let state = select_all_in_repl(state, source)

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
  assert state.mode == state.Editing
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

// --------------- 3. Evaluation -------------------------

// Reading from scratch is not the same as referencing scratch which must also work

pub fn evaluate_expression_in_shell_test() {
  let state = no_packages()
  let source = ir.integer(187)
  let state = set_repl(state, source)
  let #(state, actions) = press_key(state, "Enter")
  assert actions == []
  assert state.Editing == state.mode
  assert #(p.Exp(e.Vacant), []) == state.repl.projection

  let #(state, actions) = press_key(state, "ArrowUp")
  assert actions == []
  assert #(p.Exp(e.Integer(187)), []) == state.repl.projection
}

pub fn move_up_without_history_test() {
  let state = no_packages()
  let reason = press_key_failure(state, "ArrowUp")
  assert snippet.ActionFailed("move above") == reason
}

pub fn unknown_effect_test() {
  let state = no_packages()
  let source = ir.call(ir.perform("Launch"), [ir.string("All the missiles")])
  let state = set_repl(state, source)

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
  let state = set_repl(state, source)

  let message = state.UserPressedCommandKey("Enter")
  let #(state, actions) = state.update(state, message)
  // The ReadFile effect is synchronous in the editor so it concludes.
  assert actions == []
  let assert state.RunningShell(debug:) = state.mode
  let #(reason, _, _, _) = debug
  assert break.IncorrectTerm("String", value.Record(dict.new())) == reason
}

pub fn alert_effect_test() {
  let state = no_packages()
  let source = ir.call(ir.perform("Alert"), [ir.string("great test!")])
  let state = set_repl(state, source)

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

pub fn run_anonymous_reference_test() {
  let state = no_packages()
  let #(state, actions) = press_key(state, "#")

  assert actions == [state.FocusOnInput]
  let assert state.Picking(picker.Typing(..), ..) = state.mode

  let source = ir.integer(int.random(1_000_000))
  let assert Ok(cid) = cid.from_tree(source)
  let message = state.PickerMessage(picker.Decided(cid))

  let #(state, actions) = state.update(state, message)
  echo "should look up ref"
  assert actions == []
  let assert state.Editing = state.mode

  // let #(state, _) = press_key(state, "Enter")
  echo state.mode
  // reference state should be fetching
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

pub fn read_missing_file_test() {
  let state = no_packages()
  let source = ir.call(ir.perform("ReadFile"), [ir.string("index.eyg.json")])
  let state = set_repl(state, source)

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
  let state = set_module(state, file, ir.integer(100))
  let source = ir.call(ir.perform("ReadFile"), [ir.string(file)])
  let state = set_repl(state, source)

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

fn set_module(state, name, source) {
  let source = e.from_annotated(source)
  let projection = navigation.first(source)
  state.set_module(state, name, projection)
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

fn press_key_failure(state, key) {
  let message = state.UserPressedCommandKey(key)
  let #(state, actions) = state.update(state, message)
  let assert Some(reason) = state.user_error
  reason
}

fn read_module(state, path) {
  let state.State(modules:, ..) = state
  let assert Ok(buffer) = list.key_find(modules, path)
  buffer
}
