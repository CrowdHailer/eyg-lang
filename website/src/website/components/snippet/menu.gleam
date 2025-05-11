import gleam/list
import gleam/option.{None, Some}
import gleroglero/outline
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import morph/editable as e
import morph/projection as p

// type Action(e) {
//   Action(icon: element.Element(e), text: String, action: Message)
// }

pub type State {
  Closed
  Collection
  More
}

pub fn init() {
  Closed
}

pub fn close(_) {
  Closed
}

pub type Message {
  Toggle(State)
  ActionClicked(String)
}

pub fn update(state, message) {
  case message {
    Toggle(to) -> {
      let state = case to == state {
        False -> to
        True -> Closed
      }
      #(state, None)
    }
    ActionClicked(key) -> #(Closed, Some(key))
  }
}

fn cmd(x) {
  ActionClicked(x)
}

fn assign() {
  #(outline.equals(), "assign", cmd("e"))
}

fn assign_before() {
  #(outline.document_arrow_up(), "assign above", cmd("E"))
}

fn use_variable() {
  #(element.text("var"), "use variable", cmd("v"))
}

fn insert_function() {
  #(outline.variable(), "insert function", cmd("f"))
}

fn insert_number() {
  #(element.text("14"), "insert number", cmd("n"))
}

fn insert_text() {
  #(outline.italic(), "insert text", cmd("s"))
}

fn new_list() {
  #(element.text("[]"), "new list", cmd("l"))
}

fn new_record() {
  #(element.text("{}"), "new record", cmd("r"))
}

fn expand() {
  #(outline.arrows_pointing_out(), "expand", cmd("a"))
}

fn more() {
  #(outline.ellipsis_horizontal_circle(), "more", Toggle(More))
}

fn edit() {
  #(outline.pencil_square(), "edit", cmd("i"))
}

fn spread_list() {
  #(element.text("..]"), "spread list", cmd("."))
}

fn overwrite_field() {
  #(element.text("..}"), "overwrite field", cmd("o"))
}

fn select_field() {
  #(element.text(".x"), "select field", cmd("g"))
}

fn call_function() {
  #(element.text("(_)"), "call function", cmd("c"))
}

fn call_with() {
  #(element.text("_()"), "call as argument", cmd("w"))
}

fn tag_value() {
  #(outline.tag(), "tag value", cmd("t"))
}

fn match() {
  #(outline.arrows_right_left(), "match", cmd("m"))
}

fn branch_after() {
  #(outline.document_arrow_down(), "branch after", cmd("m"))
}

fn item_before() {
  #(outline.arrow_turn_left_down(), "item before", cmd(","))
}

fn item_after() {
  #(outline.arrow_turn_right_down(), "item after", cmd("EXTEND AFTER"))
}

fn toggle_spread() {
  #(element.text(".."), "toggle spread", cmd("TOGGLE SPREAD"))
}

fn toggle_otherwise() {
  #(element.text("_/"), "toggle otherwise", cmd("TOGGLE OTHERWISE"))
}

fn collection() {
  #(outline.arrow_down_on_square_stack(), "wrap", Toggle(Collection))
}

fn undo() {
  #(outline.arrow_uturn_left(), "undo", cmd("z"))
}

fn redo() {
  #(outline.arrow_uturn_right(), "redo", cmd("Z"))
}

pub fn delete() {
  #(outline.trash(), "delete", cmd("d"))
}

fn copy() {
  #(outline.clipboard(), "copy", cmd("y"))
}

fn paste() {
  #(outline.clipboard_document(), "paste", cmd("Y"))
}

pub fn top_content(projection) {
  let #(focus, zoom) = projection
  case focus {
    // create
    p.Exp(exp) -> {
      // Piping case into another expression produces invalid JS on 1.10.0
      let tmp = case exp {
        e.Variable(_) | e.Reference(_) | e.Release(_, _, _) -> [
          edit(),
          select_field(),
          call_function(),
          call_with(),
        ]
        e.Call(_, _) -> [select_field(), call_function(), call_with()]
        e.Function(_, _) -> [insert_function(), call_with()]
        e.Block(_, _, _) -> []
        e.Vacant -> [use_variable(), insert_number(), insert_text()]
        e.Integer(_) | e.Binary(_) | e.String(_) | e.Perform(_) | e.Deep(_) -> [
          edit(),
          call_with(),
        ]
        e.Builtin(_) -> [edit(), call_function(), call_with()]
        e.List(_, _) | e.Record(_, _) -> [toggle_spread(), call_with()]
        e.Select(_, _) -> [select_field(), call_function(), call_with()]
        e.Tag(_) -> [edit(), call_with()]
        // match open match
        e.Case(_, _, _) -> [toggle_otherwise(), call_with()]
      }
      tmp
      |> list.append([assign()], _)
      |> list.append(case zoom {
        [p.ListItem(_, _, _), ..] | [p.CallArg(_, _, _), ..] -> [
          item_before(),
          item_after(),
        ]
        [p.BlockTail(_), ..] | [] -> [assign_before()]
        _ -> []
      })
      |> list.append([collection(), more(), undo(), expand(), delete()])
    }

    p.Assign(pattern, _, _, _, _) ->
      list.flatten([
        [edit()],
        case pattern {
          p.AssignPattern(e.Bind(_)) -> [new_record()]
          p.AssignBind(_, _, _, _) | p.AssignField(_, _, _, _) -> [
            item_before(),
            item_after(),
          ]
          _ -> [assign_before()]
        },
        [undo(), expand(), delete()],
      ])
    p.Select(_, _) -> [edit(), undo(), expand(), delete()]
    p.FnParam(pattern, _, _, _) -> {
      let common = [undo(), expand(), delete()]
      case pattern {
        p.AssignPattern(e.Bind(_)) -> [
          edit(),
          item_before(),
          item_after(),
          new_record(),
          ..common
        ]
        p.AssignPattern(e.Destructure(_)) -> [
          item_before(),
          item_after(),
          ..common
        ]

        p.AssignBind(_, _, _, _) | p.AssignField(_, _, _, _) -> [
          edit(),
          item_before(),
          item_after(),
          ..common
        ]
        p.AssignStatement(_) -> [edit(), ..common]
      }
    }
    p.Label(_, _, _, _, _) -> [
      edit(),
      item_before(),
      item_after(),
      undo(),
      expand(),
      delete(),
    ]
    p.Match(_, _, _, _, _, _) -> [
      edit(),
      branch_after(),
      undo(),
      expand(),
      delete(),
    ]
  }
}

pub fn submenu_more() {
  [
    // expand(),
    redo(),
    copy(),
    paste(),
    #(outline.at_symbol(), "reference", cmd("@")),
    #(outline.bolt_slash(), "handle effect", cmd("h")),
    #(outline.bolt(), "perform effect", cmd("p")),
    #(
      h.span([a.style([#("font-size", "0.8rem")])], [element.text("1101")]),
      "binary",
      cmd("b"),
    ),
    #(outline.cog(), "builtins", cmd("j")),
  ]
}

pub fn submenu_wrap(projection) {
  let #(focus, _zoom) = projection
  case focus {
    // Show all destructure options in extra
    p.Exp(e.Variable(_)) | p.Exp(e.Call(_, _)) -> [
      spread_list(),
      overwrite_field(),
      match(),
    ]
    _ -> []
  }
  |> list.append([new_list(), new_record(), tag_value(), insert_function()])
}
