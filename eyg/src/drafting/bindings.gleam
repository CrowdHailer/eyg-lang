import gleam/option.{Some}
import drafting/session.{Binding}
import drafting/action

pub fn default() {
  [
    Binding("move up", action.move_up, Some("ArrowUp")),
    Binding("move down", action.move_down, Some("ArrowDown")),
    Binding("move left", action.move_left, Some("ArrowLeft")),
    Binding("move right", action.move_right, Some("ArrowRight")),
    Binding("increase selection", action.increase, Some("a")),
    Binding("decrease selection", action.decrease, Some("s")),
    Binding("delete", action.delete, Some("d")),
    Binding("edit", action.edit, Some("i")),
    Binding("insert variable", action.variable, Some("v")),
    Binding("create function", action.function, Some("f")),
    Binding("call function", action.call, Some("c")),
    Binding("let", action.assign, Some("e")),
    Binding("let before", action.assign_before, Some("E")),
    Binding("create string", action.string, Some("\"")),
    Binding("create list", action.list, Some("l")),
    Binding("create record", action.record, Some("r")),
    Binding("create overwrite", action.overwrite, Some("o")),
    Binding("create tag", action.tag, Some("t")),
    Binding("create match", action.match, Some("m")),
    Binding("create perform", action.perform, Some("p")),
    Binding("create builtin", action.builtin, Some("j")),
    Binding("extend", action.extend, Some(",")),
    Binding("spread list", action.spread_list, Some(".")),
    Binding("open match", action.open_match, Some("M")),
  ]
}
