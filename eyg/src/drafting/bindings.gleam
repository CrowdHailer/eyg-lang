import gleam/option.{Some}
import drafting/session.{Binding}
import drafting/action

// #(
//   "insert mode",
//   fn(zip) {
//     let assert Ok(#(value, rebuild)) = projection.text(zip)
//     State(zip, RequireString(value, rebuild))
//   },
//   Some("i"),
// ),

pub fn default() {
  [
    Binding("move up", action.move_up, Some("ArrowUp")),
    Binding("move down", action.move_down, Some("ArrowDown")),
    Binding("move left", action.move_left, Some("ArrowLeft")),
    Binding("move right", action.move_right, Some("ArrowRight")),
    Binding("increase selection", action.increase, Some("a")),
    Binding("decrease selection", action.decrease, Some("s")),
    Binding("delete", action.delete, Some("d")),
    Binding("insert variable", action.variable, Some("v")),
    Binding("create function", action.function, Some("f")),
  ]
  //   [

  //     #(
  //       "call function",
  //       fn(zip) {
  //         let assert Ok(zip) = transformation.call(zip)
  //         State(zip, Navigate)
  //       },
  //       Some("c"),
  //     ),
  //     #(
  //       "let",
  //       fn(zip) {
  //         let assert Ok(rebuild) = transformation.assign(zip)
  //         update_focus()
  //         State(zip, RequireString("", fn(label) { rebuild(e.Bind(label)) }))
  //       },
  //       Some("e"),
  //     ),
  //     #("let above", fn(zip) { todo }, None),
  //     #(
  //       "string",
  //       fn(zip) {
  //         let assert Ok(#(value, rebuild)) = transformation.string(zip)
  //         State(zip, RequireString(value, rebuild))
  //       },
  //       Some("\""),
  //     ),
  //     #(
  //       "list",
  //       fn(zip) {
  //         let assert Ok(zip) = transformation.list(zip)
  //         State(zip, Navigate)
  //       },
  //       Some("l"),
  //     ),
  //     #(
  //       "extend list",
  //       fn(zip) {
  //         case transformation.extend_list(zip) {
  //           transformation.NeedString(rebuild) ->
  //             State(zip, RequireString("", rebuild))
  //           transformation.NoString(zip) -> State(zip, Navigate)
  //         }
  //       },
  //       Some(","),
  //     ),
  //     #(
  //       "spread list",
  //       fn(zip) {
  //         let assert Ok(zip) = transformation.spread_list(zip)
  //         State(zip, Navigate)
  //       },
  //       Some("."),
  //     ),
  //     #(
  //       "record",
  //       fn(zip) {
  //         case transformation.record(zip) {
  //           Ok(transformation.NeedString(rebuild)) ->
  //             State(zip, RequireString("", rebuild))
  //           Ok(transformation.NoString(zip)) -> State(zip, Navigate)
  //           _ -> panic as "no action for record"
  //         }
  //       },
  //       Some("r"),
  //     ),
  //     #(
  //       "overwrite",
  //       fn(zip) {
  //         let assert Ok(rebuild) = transformation.overwrite(zip)
  //         update_focus()
  //         State(zip, RequireString("", fn(label) { rebuild(label) }))
  //       },
  //       Some("o"),
  //     ),
  //     #(
  //       "tag",
  //       fn(zip) {
  //         let assert Ok(rebuild) = transformation.tag(zip)
  //         update_focus()
  //         State(zip, RequireString("", fn(label) { rebuild(label) }))
  //       },
  //       Some("t"),
  //     ),
  //     #(
  //       "match",
  //       fn(zip) {
  //         let assert Ok(rebuild) = transformation.match(zip)
  //         update_focus()
  //         State(zip, RequireString("", fn(label) { rebuild(label) }))
  //       },
  //       Some("m"),
  //     ),
  //     #(
  //       "open match",
  //       fn(zip) {
  //         let assert Ok(zip) = transformation.open_match(zip)
  //         update_focus()
  //         State(zip, Navigate)
  //       },
  //       Some("M"),
  //     ),
  //     #(
  //       "builtin",
  //       fn(zip) {
  //         let assert Ok(#(value, rebuild)) = transformation.builtin(zip)
  //         State(zip, RequireString(value, rebuild))
  //       },
  //       Some("j"),
  //     ),
  //   ]
}
