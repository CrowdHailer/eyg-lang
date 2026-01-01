import eyg/analysis/inference/levels_j/contextual
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/break
import eyg/interpreter/value
import eyg/ir/cid
import eyg/ir/dag_json
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
import website/components/shell
import website/components/snippet
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

  let #(state, _actions) = press_key(state, "L")
  assert [] == actions
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

pub fn vertical_move_in_file_test() {
  let state = no_packages()
  let state =
    set_module(
      state,
      #("foo", state.EygJson),
      ir.let_("x", ir.string("a"), ir.unit()),
    )
  let state =
    state.State(..state, focused: state.Module(#("foo", state.EygJson)))
  let reason = press_key_failure(state, "ArrowUp")
  assert snippet.ActionFailed("move above") == reason

  let #(state, actions) = press_key(state, "ArrowDown")
  assert [] == actions
  let module = read_module(state, #("foo", state.EygJson))
  let assert #(p.Exp(e.Record([], None)), [p.BlockTail(..)]) = module.projection

  let reason = press_key_failure(state, "ArrowDown")
  assert snippet.ActionFailed("move below") == reason

  let #(state, actions) = press_key(state, "ArrowUp")
  assert [] == actions
  let module = read_module(state, #("foo", state.EygJson))
  let assert #(
    p.Assign(
      p.AssignStatement(e.Bind("x")),
      e.String("a"),
      [],
      [],
      e.Record([], None),
    ),
    [],
  ) = module.projection
}

pub fn navigate_back_to_shell_test() {
  let state = no_packages()
  let name = "bar"
  let state =
    set_module(
      state,
      #(name, state.EygJson),
      ir.let_("x", ir.string("a"), ir.unit()),
    )
  let state =
    state.State(..state, focused: state.Module(#(name, state.EygJson)))

  // assert =
  assert snippet.ActionFailed(action: "Can't execute module")
    == press_key_failure(state, "Enter")

  let #(state, actions) = press_key(state, "Escape")
  assert [] == actions
  assert state.Repl == state.focused
}

// --------------- 2. Editing -------------------------

pub fn variable_insert_test() {
  let state = no_packages()
  let source = ir.let_("user", ir.string("tim"), ir.vacant())
  let state = set_repl(state, source)
  let #(state, actions) = press_key(state, " ")
  assert [] == actions
  let #(state, actions) = press_key(state, "v")
  assert [] == actions
  let assert state.Picking(picker:, ..) = state.mode
  let assert picker.Typing(value: "", suggestions:) = picker
  assert [#("user", "String")] == suggestions
}

pub fn cant_insert_variable_on_assignment_test() {
  let state = no_packages()
  let source = ir.let_("x", ir.integer(7), ir.unit())
  let state = set_repl(state, source)
  let reason = press_key_failure(state, "v")
  assert snippet.ActionFailed(action: "insert variable") == reason
}

pub fn insert_function_test() {
  let state = no_packages()
  let #(state, actions) = press_key(state, "f")
  assert [state.FocusOnInput] == actions
  let assert state.Picking(picker:, ..) = state.mode
  assert picker.Typing("", []) == picker
}

pub fn call_function_chooses_argument_count_test() {
  let state = no_packages()
  let source = ir.builtin("equal")
  let state = set_repl(state, source)
  let #(state, actions) = press_key(state, "c")
  assert [] == actions
  assert #(p.Exp(e.Vacant), [p.CallArg(e.Builtin("equal"), [], [e.Vacant])])
    == state.repl.projection
}

pub fn call_single_argument_test() {
  let state = no_packages()
  let source = ir.builtin("equal")
  let state = set_repl(state, source)
  let #(state, actions) = press_key(state, "C")
  assert [] == actions
  assert #(p.Exp(e.Vacant), [p.CallArg(e.Builtin("equal"), [], [])])
    == state.repl.projection
}

pub fn call_with_argument_test() {
  let state = no_packages()
  let source = ir.integer(44)
  let state = set_repl(state, source)
  let #(state, actions) = press_key(state, "w")
  assert [] == actions
  assert #(p.Exp(e.Vacant), [p.CallFn([e.Integer(44)])])
    == state.repl.projection
}

pub fn insert_binary_test() {
  let state = no_packages()
  let #(state, actions) = press_key(state, "b")
  assert [] == actions
  let assert state.Editing = state.mode
  assert #(p.Exp(e.Binary(<<>>)), []) == state.repl.projection
}

pub fn insert_string_test() {
  let state = no_packages()
  let #(state, actions) = press_key(state, "s")
  assert [state.FocusOnInput] == actions
  let assert state.EditingText(value:, ..) = state.mode
  assert "" == value

  let message = state.InputMessage(input.UpdateInput("silly."))
  let #(state, actions) = state.update(state, message)
  assert [] == actions
  let assert state.EditingText(value:, ..) = state.mode
  assert "silly." == value

  let message = state.InputMessage(input.Submit)
  let #(state, actions) = state.update(state, message)
  assert [] == actions
  assert state.Editing == state.mode
  assert #(p.Exp(e.String("silly.")), []) == state.repl.projection
}

pub fn cancel_string_insert_test() {
  let state = no_packages()
  let #(state, actions) = press_key(state, "s")
  assert [state.FocusOnInput] == actions
  let assert state.EditingText(value:, ..) = state.mode
  assert "" == value

  let message = state.InputMessage(input.UpdateInput("silly."))
  let #(state, actions) = state.update(state, message)
  assert [] == actions
  let assert state.EditingText(value:, ..) = state.mode
  assert "silly." == value

  let message = state.InputMessage(input.KeyDown("Escape"))
  let #(state, actions) = state.update(state, message)
  assert [] == actions
  assert state.Editing == state.mode
  assert #(p.Exp(e.Vacant), []) == state.repl.projection
}

pub fn insert_integer_test() {
  let state = no_packages()
  let #(state, actions) = press_key(state, "n")
  assert [state.FocusOnInput] == actions
  let assert state.EditingInteger(value:, ..) = state.mode
  assert 0 == value

  let message = state.InputMessage(input.UpdateInput("28"))
  let #(state, actions) = state.update(state, message)
  assert [] == actions
  let assert state.EditingInteger(value:, ..) = state.mode
  assert 28 == value

  let message = state.InputMessage(input.Submit)
  let #(state, actions) = state.update(state, message)
  assert [] == actions
  assert state.Editing == state.mode
  assert #(p.Exp(e.Integer(28)), []) == state.repl.projection
}

pub fn cancel_integer_insert_test() {
  let state = no_packages()
  let #(state, actions) = press_key(state, "n")
  assert [state.FocusOnInput] == actions
  let assert state.EditingInteger(value:, ..) = state.mode
  assert 0 == value

  let message = state.InputMessage(input.UpdateInput("95"))
  let #(state, actions) = state.update(state, message)
  assert [] == actions
  let assert state.EditingInteger(value:, ..) = state.mode
  assert 95 == value

  let message = state.InputMessage(input.KeyDown("Escape"))
  let #(state, actions) = state.update(state, message)
  assert [] == actions
  assert state.Editing == state.mode
  assert #(p.Exp(e.Vacant), []) == state.repl.projection
}

pub fn insert_list_test() {
  let state = no_packages()
  let source = ir.integer(22)
  let state = set_repl(state, source)
  let #(state, actions) = press_key(state, "l")
  assert [] == actions
  assert state.Editing == state.mode
}

pub fn extend_list_before_test() {
  let state = no_packages()
  let source = ir.list([ir.integer(85)])
  let state = set_repl(state, source)

  let #(state, actions) = press_key(state, "<")
  assert [] == actions
  assert state.Editing == state.mode
  assert #(p.Exp(e.Vacant), [p.ListItem([], [e.Integer(85)], None)])
    == state.repl.projection
}

pub fn insert_record_test() {
  let state = no_packages()
  let source = ir.call(ir.select("location"), [ir.vacant()])
  let state = set_repl(state, source)
  let #(state, actions) = press_key(state, "r")
  // Type infor not working properly
  // assert [] == actions
  // echo state.mode

  // todo
}

// insert record on assignment

pub fn select_typed_field_test() {
  let state = no_packages()
  let source = ir.record([#("sweet", ir.true()), #("size", ir.integer(3))])
  let state = select_all_in_repl(state, source)

  let #(state, actions) = press_key(state, "g")
  assert actions == [state.FocusOnInput]
  let assert state.Picking(picker:, ..) = state.mode
  let assert picker.Typing(value: "", suggestions:) = picker
  assert list.length(suggestions) == 2
  assert Ok("Integer") == list.key_find(suggestions, "size")

  // The picker is weird in that it updates the whole state in the message, and the list of suggestions is constant
  let new = picker.Typing("si", suggestions)
  let message = state.PickerMessage(picker.Updated(new))
  let #(state, actions) = state.update(state, message)
  assert actions == []
  let assert state.Picking(picker:, ..) = state.mode
  assert new == picker
}

pub fn overwrite_test() {
  let state = no_packages()
  let source = ir.record([#("pink", ir.true()), #("distance", ir.integer(3))])
  let state = select_all_in_repl(state, source)

  let #(state, actions) = press_key(state, "o")
  assert actions == [state.FocusOnInput]
  let assert state.Picking(picker:, ..) = state.mode
  let assert picker.Typing(value: "", suggestions:) = picker
  assert list.length(suggestions) == 2
  assert Ok("Integer") == list.key_find(suggestions, "distance")
}

pub fn tag_on_vacant_test() {
  let state = no_packages()
  let #(state, actions) = press_key(state, "t")
  assert actions == [state.FocusOnInput]
  let assert state.Picking(picker:, ..) = state.mode
  let assert picker.Typing(value: "", suggestions:) = picker
  assert [] == suggestions
}

pub fn tag_with_hints_test() {
  let state = no_packages()
  let source =
    ir.match(ir.vacant(), [
      #("Apples", ir.lambda("_", ir.vacant())),
      #("Oranges", ir.lambda("_", ir.vacant())),
    ])
  let state = set_repl(state, source)

  let #(state, actions) = press_key(state, "t")
  assert actions == [state.FocusOnInput]
  let assert state.Picking(picker:, ..) = state.mode
  let assert picker.Typing(value: "", suggestions:) = picker
  assert [#("Apples", "0"), #("Oranges", "11")] == suggestions
}

pub fn auto_match_test() {
  let state = no_packages()
  let source = ir.call(ir.builtin("equal"), [ir.integer(1), ir.integer(2)])
  let state = select_all_in_repl(state, source)
  let #(state, actions) = press_key(state, "m")
  assert actions == []
  assert state.mode == state.Editing
}

pub fn cant_match_test() {
  let state = no_packages()
  let source = ir.let_("here", ir.vacant(), ir.vacant())
  let state = set_repl(state, source)
  press_key_failure(state, "m")
}

pub fn insert_builtin_test() {
  let state = no_packages()
  let #(state, actions) = press_key(state, "j")
  assert actions == [state.FocusOnInput]
  assert state.user_error == None
  let assert state.Picking(picker:, ..) = state.mode
  let assert picker.Typing(suggestions:, ..) = picker
  assert list.key_find(suggestions, "int_to_string")
    == Ok("(Integer) -> String")
}

pub fn suggest_shell_effects_test() {
  let state = no_packages()
  let #(state, actions) = press_key(state, "p")
  assert actions == []
  assert state.user_error == None
  let assert state.Picking(picker:, ..) = state.mode
  let assert picker.Typing(suggestions:, ..) = picker
  assert list.key_find(suggestions, "Alert") == Ok("String : {}")
}

pub fn cant_set_expression_on_assignment_test() {
  let state = no_packages()
  let source = ir.let_("here", ir.vacant(), ir.vacant())
  let state = set_repl(state, source)
  press_key_failure(state, "L")
}

pub fn simple_edit_in_module_test() {
  // open module
  let state = no_packages()
  let source = ir.call(ir.perform("Open"), [ir.string("user")])
  let state = set_repl(state, source)
  let #(state, actions) = press_key(state, "Enter")
  assert actions == []
  assert state.Module(#("user", state.EygJson)) == state.focused
  assert state.Editing == state.mode
  assert #(p.Exp(e.Vacant), []) == state.repl.projection
  let assert [shell.Executed(value:, effects:, ..)] = state.previous
  assert Some(value.ok(value.unit())) == value
  let assert [#("Open", #(lift, reply))] = effects
  assert value.String("user") == lift
  assert value.ok(value.unit()) == reply

  let #(state, actions) = press_key(state, "R")
  assert [] == actions
  assert state.Module(#("user", state.EygJson)) == state.focused
  assert state.Editing == state.mode
  let assert #(p.Exp(e.Record([], None)), []) =
    read_module(state, #("user", state.EygJson)).projection
}

pub fn bad_open_arg_test() {
  // open module
  let state = no_packages()
  let source = ir.call(ir.perform("Open"), [ir.unit()])
  let state = set_repl(state, source)
  let #(state, actions) = press_key(state, "Enter")
  assert actions == []

  let assert state.RunningShell(awaiting: None, debug:, ..) = state.mode
  assert break.IncorrectTerm("String", value.Record(dict.from_list([])))
    == debug.0
}

pub fn enter_insert_mode_test() {
  let state = no_packages()
  let source = ir.string("straberry")
  let state = set_repl(state, source)
  let #(state, actions) = press_key(state, "i")
  assert [state.FocusOnInput] == actions
  let assert state.Picking(picker: picker.Typing(value:, ..), ..) = state.mode
  assert "straberry" == value
}

pub fn cant_delete_nothing_test() {
  let state = no_packages()
  let reason = press_key_failure(state, "d")
  assert snippet.ActionFailed("delete") == reason
}

// --------------- undo/redo -------------------------
pub fn undo_redo_test() {
  let state = no_packages()
  let #(state, actions) = press_key(state, "R")
  assert [] == actions
  assert #(p.Exp(e.Record([], None)), []) == state.repl.projection

  let #(state, actions) = press_key(state, "z")
  assert [] == actions
  assert #(p.Exp(e.Vacant), []) == state.repl.projection

  let reason = press_key_failure(state, "z")
  assert snippet.ActionFailed("undo") == reason

  let #(state, actions) = press_key(state, "Z")
  assert [] == actions
  assert #(p.Exp(e.Record([], None)), []) == state.repl.projection

  let reason = press_key_failure(state, "Z")
  assert snippet.ActionFailed("redo") == reason
}

pub fn reset_redo_with_edit_test() {
  let state = no_packages()
  let #(state, actions) = press_key(state, "R")
  assert [] == actions

  let #(state, actions) = press_key(state, "z")
  assert [] == actions

  let #(state, actions) = press_key(state, "L")
  assert [] == actions

  let reason = press_key_failure(state, "Z")
  assert snippet.ActionFailed("redo") == reason
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
  let assert state.ReadingFromClipboard(..) = state.mode
  let message =
    state.ClipboardReadCompleted(Ok("{\"0\":\"s\",\"v\":\"Wallpaper\"}"))
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert state.user_error == None
  assert state.mode == state.Editing
}

pub fn cant_paste_on_assignment_test() {
  let state = no_packages()
  let source = ir.let_("here", ir.vacant(), ir.vacant())
  let state = set_repl(state, source)
  let reason = press_key_failure(state, "Y")
  assert snippet.ActionFailed("paste") == reason
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

pub fn evaluate_bad_expression_in_shell_test() {
  let state = no_packages()
  let source = ir.variable("vanished")
  let state = set_repl(state, source)
  let #(state, actions) = press_key(state, "Enter")
  assert actions == []
  let assert state.RunningShell(awaiting:, debug:, ..) = state.mode
  assert None == awaiting
  assert break.UndefinedVariable("vanished") == debug.0
  assert #(p.Exp(e.Variable("vanished")), []) == state.repl.projection

  let #(state, actions) = press_key(state, "L")
  assert actions == []
  assert state.Editing == state.mode
  assert #(p.Exp(e.List([], None)), []) == state.repl.projection
}

pub fn unknown_effect_test() {
  let state = no_packages()
  let source = ir.call(ir.perform("Launch"), [ir.string("All the missiles")])
  let state = set_repl(state, source)
  assert [#([], error.MissingRow("Launch"))]
    == contextual.all_errors(state.repl.analysis)

  let message = state.UserPressedCommandKey("Enter")
  let #(state, actions) = state.update(state, message)

  assert actions == []
  // Should the error be on the shell or a key press error
  let assert state.RunningShell(debug:, ..) = state.mode
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
  assert [#([], error.TypeMismatch(t.Record(t.Empty), t.String))]
    == contextual.all_errors(state.repl.analysis)

  let message = state.UserPressedCommandKey("Enter")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  let assert state.RunningShell(debug:, ..) = state.mode
  let #(reason, _, _, _) = debug
  assert break.IncorrectTerm("String", value.Record(dict.new())) == reason
}

pub fn multiple_effect_test() {
  let state = no_packages()
  let source =
    ir.let_(
      "_",
      ir.call(ir.perform("Alert"), [ir.string("great test!")]),
      ir.call(ir.perform("Alert"), [ir.string("Next test")]),
    )
  let state = set_repl(state, source)
  assert [] == contextual.all_errors(state.repl.analysis)

  let message = state.UserPressedCommandKey("Enter")

  let #(state, actions) = state.update(state, message)
  assert actions == [state.RunEffect(1, state.Alert("great test!"))]
  let assert state.RunningShell(awaiting:, ..) = state.mode
  assert Some(1) == awaiting

  let message = state.EffectImplementationCompleted(1, value.unit())
  let #(state, actions) = state.update(state, message)
  assert actions == [state.RunEffect(2, state.Alert("Next test"))]
  let assert state.RunningShell(..) = state.mode

  let message = state.EffectImplementationCompleted(2, value.unit())
  let #(state, actions) = state.update(state, message)
  assert [] == actions
  let assert state.Editing = state.mode

  let assert [shell.Executed(value:, effects:, ..)] = state.previous
  assert Some(value.Record(dict.from_list([]))) == value
  let assert [one, two] = effects
  assert #("Alert", #(
      value.String("great test!"),
      value.Record(dict.from_list([])),
    ))
    == one
  assert #("Alert", #(
      value.String("Next test"),
      value.Record(dict.from_list([])),
    ))
    == two
}

pub fn cancel_running_effect_test() {
  let state = no_packages()
  let source = ir.call(ir.perform("Alert"), [ir.string("annoying")])
  let state = set_repl(state, source)

  let #(state, actions) = press_key(state, "Enter")
  assert actions == [state.RunEffect(1, state.Alert("annoying"))]
  let assert state.RunningShell(awaiting: Some(1), ..) = state.mode

  let #(state, actions) = press_key(state, "Escape")
  assert [] == actions
  let assert state.Editing = state.mode
  // TODO move to flip and show that a subsequent request doesn't race

  let message = state.EffectImplementationCompleted(1, value.unit())
  let #(state, actions) = state.update(state, message)
  assert [] == actions
  let assert state.Editing = state.mode
  assert [] == state.previous

  let #(state, actions) = press_key(state, "Enter")
  assert actions == [state.RunEffect(2, state.Alert("annoying"))]
  let assert state.RunningShell(awaiting: Some(2), ..) = state.mode

  // async effect returning after cancellation and restart will be ignored
  let message = state.EffectImplementationCompleted(1, value.unit())
  let #(state, actions) = state.update(state, message)
  assert [] == actions
  let assert state.RunningShell(awaiting: Some(2), ..) = state.mode
}

pub fn abort_effect_test() {
  let state = no_packages()
  let source = ir.call(ir.perform("Abort"), [ir.string("nope")])
  let state = set_repl(state, source)
  assert [] == contextual.all_errors(state.repl.analysis)

  let #(state, actions) = press_key(state, "Enter")
  assert actions == []
  let assert state.RunningShell(awaiting: None, ..) = state.mode
}

pub fn bad_abort_input_effect_test() {
  let state = no_packages()
  let source = ir.call(ir.perform("Abort"), [ir.unit()])
  let state = set_repl(state, source)

  let message = state.UserPressedCommandKey("Enter")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  let assert state.RunningShell(debug:, ..) = state.mode
  let #(reason, _, _, _) = debug
  assert break.IncorrectTerm("String", value.Record(dict.new())) == reason
}

pub fn cant_have_effects_in_modules_test() {
  let state = no_packages()
  let source = ir.call(ir.perform("Alert"), [ir.string("nope")])
  let name = #("a", state.EygJson)
  let state = set_module(state, name, source)
  let state = state.State(..state, focused: state.Module(name))

  let assert Ok(buffer) = dict.get(state.modules, name)
  assert [#([], error.MissingRow("Alert"))]
    == contextual.all_errors(buffer.analysis)
}

// --------------- 4. block eval -------------------------

pub fn shell_scope_test() {
  let state = no_packages()
  let source = ir.let_("x", ir.integer(171), ir.vacant())
  let state = set_repl(state, source)
  let #(state, actions) = press_key(state, "Enter")
  assert [] == actions
  let assert state.Editing = state.mode
  let assert [shell.Executed(value: None, ..)] = state.previous

  let #(state, actions) = press_key(state, "v")
  assert [] == actions
  let assert state.Picking(picker:, ..) = state.mode

  let assert [#("x", "Integer")] = picker.suggestions

  let message = state.PickerMessage(picker.Decided("x"))
  let #(state, actions) = state.update(state, message)
  assert [] == actions
  assert state.Editing == state.mode

  let #(state, actions) = press_key(state, "Enter")
  assert [] == actions
  assert state.Editing == state.mode
  let assert [shell.Executed(value: Some(value.Integer(171)), ..), _] =
    state.previous
}

// --------------- 4. References -------------------------
pub fn run_anonymous_reference_test() {
  let state = no_packages()
  let #(state, actions) = press_key(state, "#")

  assert actions == [state.FocusOnInput]
  let assert state.Picking(picker.Typing(..), ..) = state.mode

  let rand = int.random(1_000_000)
  let source = ir.integer(rand)
  let assert Ok(cid) = cid.from_tree(source)
  let message = state.PickerMessage(picker.Decided(cid))

  let #(state, actions) = state.update(state, message)
  let assert [state.SyncAction(client.FetchFragments(cids:, ..))] = actions
  assert [cid] == cids
  let assert state.Editing = state.mode

  let assert [err] = contextual.all_errors(state.repl.analysis)
  assert #([], error.MissingReference(cid)) == err

  let response = server.fetch_fragment_response(source)
  let message = state.SyncMessage(client.FragmentFetched(cid, Ok(response)))
  let #(state, actions) = state.update(state, message)
  assert [] == actions
  let assert [] = contextual.all_errors(state.repl.analysis)

  let #(state, actions) = press_key(state, "Enter")
  assert [] == actions

  let assert state.Editing = state.mode
  // echo state.previous
}

pub fn fails_on_unknown_reference_test() {
  let state = no_packages()

  // Don't make this available
  let rand = int.random(1_000_000)
  let lib = ir.integer(rand)
  let assert Ok(cid) = cid.from_tree(lib)

  let state = set_repl(state, ir.reference(cid))
  let #(state, actions) = press_key(state, "Enter")
  assert [] == actions
  let assert state.RunningShell(awaiting:, debug:, ..) = state.mode
  assert None == awaiting
  assert break.UndefinedReference(cid) == debug.0
}

// TODO running with a reference stays present

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
  let assert state.ChoosingPackage(..) = state.mode
  assert state.Repl == state.focused

  let assert [release] = state.package_choice(state)
  let assert analysis.Release(package: "foo", version: 1, ..) = release

  let message = state.PickerMessage(picker.Decided("foo"))
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert state.Editing == state.mode
  assert state.Repl == state.focused

  assert [] == contextual.all_errors(state.repl.analysis)

  let message = state.UserPressedCommandKey("Enter")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert state.Editing == state.mode
}

pub fn read_missing_source_file_test() {
  let state = no_packages()
  let source = ir.call(ir.perform("ReadFile"), [ir.string("index.eyg.json")])
  let state = set_repl(state, source)

  let message = state.UserPressedCommandKey("Enter")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert state.Editing == state.mode
  let assert [shell.Executed(value:, ..)] = state.previous
  assert Some(value.Tagged("Error", value.String("No file"))) == value
}

pub fn read_missing_file_test() {
  let state = no_packages()
  let source = ir.call(ir.perform("ReadFile"), [ir.string("index.txt")])
  let state = set_repl(state, source)

  let message = state.UserPressedCommandKey("Enter")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert state.Editing == state.mode
  let assert [shell.Executed(value:, ..)] = state.previous
  assert Some(value.Tagged("Error", value.String("No file"))) == value
}

pub fn read_source_file_test() {
  let state = no_packages()
  let file = "index"
  let lib = ir.integer(100)
  let state = set_module(state, #(file, state.EygJson), lib)
  let source = ir.call(ir.perform("ReadFile"), [ir.string(file <> ".eyg.json")])
  let state = set_repl(state, source)

  let message = state.UserPressedCommandKey("Enter")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert state.Editing == state.mode
  let assert [shell.Executed(value:, ..)] = state.previous
  let assert Some(value.Tagged("Ok", value.Binary(bytes))) = value
  assert dag_json.to_block(lib) == bytes
}

// --------------- 7. Relative references -------------------------

// track the references in the buffer
pub fn read_reference_from_repl_test() {
  let state = no_packages()
  let file = "index"
  let rand = int.random(1_000_000)
  let lib = ir.integer(rand)
  let assert Ok(cid) = cid.from_tree(lib)
  let state = set_module(state, #(file, state.EygJson), lib)

  let ref = ir.release("./index", 0, "./index")
  let source = ir.call(ir.builtin("int_add"), [ref, ir.integer(1)])
  let state = set_repl(state, source)

  assert [] == contextual.all_errors(state.repl.analysis)

  let message = state.UserPressedCommandKey("Enter")
  let #(state, actions) = state.update(state, message)
  assert actions == []
  assert state.Editing == state.mode
  let assert [shell.Executed(value: Some(value), ..)] = state.previous
  assert value.Integer(rand + 1) == value
}

// Fails for bad cid
// type checking updates
// cant create circular references

// --------------- Helpers -------------------------
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
  assert [] == actions
  let assert Some(reason) = state.user_error
  reason
}

fn read_module(state, path) {
  let state.State(modules:, ..) = state
  let assert Ok(buffer) = dict.get(modules, path)
  buffer
}
