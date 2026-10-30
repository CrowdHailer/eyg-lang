//// buffer doesn't define UI components, or grouping of actions.
//// All actions might be presented differently in different UI
//// 
//// Return types from the buffer actions are not enough to know how to present choices
//// 
//// A top level application might create an enum of editing modes

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/error
import eyg/analysis/type_/isomorphic as iso
import eyg/ir/dag_json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import morph/action
import morph/analysis
import morph/editable as e
import morph/navigation
import morph/projection as p
import morph/transformation as t

pub type Buffer {
  Buffer(
    history: History,
    projection: p.Projection,
    analysis: Option(infer.Analysis(List(Int))),
  )
}

pub type History {
  History(undo: List(p.Projection), redo: List(p.Projection))
}

pub const empty_history = History([], [])

fn history_new_entry(old, history) {
  let History(undo: undo, ..) = history
  let undo = [old, ..undo]
  History(undo: undo, redo: [])
}

/// Restoring code invalidates its analysis; dependencies and scope may differ.
pub fn undo(buffer) {
  let Buffer(history:, projection:, ..) = buffer

  case history.undo {
    [first, ..rest] -> {
      let redo = [projection, ..history.redo]
      let history = History(undo: rest, redo:)
      Ok(Buffer(history:, projection: first, analysis: None))
    }
    [] -> Error(Nil)
  }
}

pub fn redo(buffer) {
  let Buffer(history:, projection:, ..) = buffer
  case history.redo {
    [first, ..rest] -> {
      let undo = [projection, ..history.undo]
      let history = History(undo:, redo: rest)
      Ok(Buffer(history:, projection: first, analysis: None))
    }
    [] -> Error(Nil)
  }
}

/// Check the current code. The caller resolves each reference and drives the
/// steps to completion, including when a reference is not available yet.
pub fn check(buffer: Buffer, context: infer.Context) -> infer.Step(Buffer) {
  use analysis <- infer.bind(infer.check(context, source(buffer)))
  infer.Done(Buffer(..buffer, analysis: Some(analysis)))
}

/// Invalidate analysis when the caller's scope or dependencies change.
pub fn invalidate(buffer: Buffer) -> Buffer {
  Buffer(..buffer, analysis: None)
}

pub fn empty() {
  from_projection(p.empty)
}

pub fn from_source(source) {
  source
  |> e.from_annotated
  |> p.all()
  |> from_projection
}

pub fn from_projection(projection) {
  Buffer(history: empty_history, projection:, analysis: None)
}

pub fn update_code(buffer, new) {
  let Buffer(history:, projection: old, ..) = buffer
  let history = history_new_entry(old, history)
  Buffer(history:, projection: new, analysis: None)
}

pub fn update_position(buffer, projection) {
  Buffer(..buffer, projection:)
}

/// Returns information for the selection, if checked and its annotation exists.
pub fn target_info(buffer: Buffer) -> Result(infer.NodeInfo, Nil) {
  let Buffer(projection:, analysis:, ..) = buffer
  let path = p.path(projection)
  use analysis <- result.try(option.to_result(analysis, Nil))
  infer.info_at(analysis, list.reverse(path))
}

pub fn target_type(buffer) {
  use info <- result.map(target_info(buffer))
  info.type_
}

/// Return the type under the selection
/// This approach is a bit heavy and doesn't handle match/select
pub fn selection_type(buffer: Buffer) -> Result(iso.Type(Int), Nil) {
  case buffer.projection {
    #(p.Exp(_), _) -> target_type(buffer)
    #(p.Assign(pattern, value, pre, post, tail), zoom) -> {
      let definition = #(p.Exp(value), [
        p.BlockValue(p.assigned_pattern(pattern), pre, post, tail),
        ..zoom
      ])
      use type_ <- result.try(target_type(
        Buffer(..buffer, projection: definition),
      ))
      pattern_type(pattern, type_)
    }
    #(p.FnParam(pattern, pre, post, body), zoom) -> {
      let params =
        list.append(list.reverse(pre), [p.assigned_pattern(pattern), ..post])
      let function = #(p.Exp(e.Function(params, body)), zoom)
      use type_ <- result.try(target_type(
        Buffer(..buffer, projection: function),
      ))
      use argument <- result.try(argument_type(type_, list.length(pre)))
      pattern_type(pattern, argument)
    }
    _ -> Error(Nil)
  }
}

fn pattern_type(pattern: p.AssignFocus, type_: iso.Type(Int)) {
  case pattern {
    p.AssignStatement(_) | p.AssignPattern(_) -> Ok(type_)
    p.AssignField(label, _, _, _) | p.AssignBind(label, _, _, _) ->
      case type_ {
        iso.Record(rows) -> row_type(rows, label)
        _ -> Error(Nil)
      }
  }
}

fn argument_type(type_: iso.Type(Int), index: Int) {
  case type_ {
    iso.Fun(argument, _, _) if index == 0 -> Ok(argument)
    iso.Fun(_, _, returned) if index > 0 -> argument_type(returned, index - 1)
    _ -> Error(Nil)
  }
}

fn row_type(rows: iso.Type(Int), label: String) {
  case rows {
    iso.RowExtend(field, value, _) if field == label -> Ok(value)
    iso.RowExtend(_, _, rest) -> row_type(rest, label)
    _ -> Error(Nil)
  }
}

/// Diagnostics available so far. An unchecked buffer has no diagnostics;
/// callers must inspect `analysis` before treating the code as checked.
pub fn errors(buffer: Buffer) {
  case buffer.analysis {
    None -> []
    Some(analysis) -> infer.all_errors(analysis)
  }
}

pub fn block_errors(buffer: Buffer) {
  errors(buffer)
  |> list.filter(fn(error) {
    let #(path, reason) = error
    let is_vacant = reason == error.Todo
    let last = case path {
      [] | [_] -> True
      _ -> False
    }
    !{ last && is_vacant }
  })
}

pub fn fields(buffer) {
  case target_type(buffer) {
    Ok(iso.Record(rows)) -> analysis.rows(rows)
    _ -> []
  }
}

pub fn variants(buffer) {
  case target_type(buffer) {
    Ok(iso.Union(rows)) -> analysis.rows(rows)
    _ -> []
  }
}

pub fn target_scope(buffer) {
  use info <- result.map(target_info(buffer))
  info.scope
}

pub fn target_arity(buffer) {
  use type_ <- result.try(target_type(buffer))
  infer.count_args(type_)
}

// ------------------------- Navigations
fn navigate(buffer: Buffer, navigation) {
  use projection <- result.map(navigation(buffer.projection))
  update_position(buffer, projection)
}

fn always_navigate(state, navigation) {
  navigate(state, fn(p) { Ok(navigation(p)) })
}

pub fn next(state) {
  always_navigate(state, navigation.next)
}

pub fn previous(state) {
  always_navigate(state, navigation.previous)
}

pub fn up(state) {
  navigate(state, navigation.move_up)
}

pub fn down(state) {
  navigate(state, navigation.move_down)
}

pub fn increase(buffer: Buffer) {
  navigate(buffer, navigation.increase)
}

pub fn next_vacant(buffer) {
  navigate(buffer, navigation.next_vacant)
}

pub fn toggle_open(buffer) {
  navigate(buffer, navigation.toggle_open)
}

pub fn focus_at(buffer: Buffer, path) {
  navigate(buffer, navigate_focus_at(_, path))
}

fn navigate_focus_at(projection, path) {
  Ok(p.focus_at(p.rebuild(projection), path))
}

pub fn focus_at_reversed(buffer: Buffer, reversed) {
  focus_at(buffer, list.reverse(reversed))
}

// ------------------------- Transformations

pub type Continue {
  Done(Buffer)
  WithString(fn(String) -> Buffer)
}

pub fn set_expression(buffer: Buffer) {
  case buffer.projection {
    #(p.Exp(_old), zoom) ->
      Ok(fn(new) { update_code(buffer, #(p.Exp(new), zoom)) })
    _ -> Error(Nil)
  }
}

pub fn insert(buffer: Buffer) {
  use #(value, rebuild) <- result.map(case buffer.projection {
    #(p.Exp(e.String(value)), zoom) -> {
      Ok(#(value, fn(value) { #(p.Exp(e.String(value)), zoom) }))
    }
    _ -> p.text(buffer.projection)
  })
  #(value, fn(new) { update_code(buffer, rebuild(new)) })
}

pub fn insert_before(buffer: Buffer) {
  use new <- result.map(action.extend_before(buffer.projection))
  case new {
    action.Updated(new) -> Done(update_code(buffer, new))
    action.Choose(rebuild:, ..) ->
      WithString(fn(label) { update_code(buffer, rebuild(label)) })
  }
}

pub fn insert_after(buffer: Buffer) {
  use new <- result.map(action.extend_after(buffer.projection))
  case new {
    action.Updated(new) -> Done(update_code(buffer, new))
    action.Choose(rebuild:, ..) ->
      WithString(fn(label) { update_code(buffer, rebuild(label)) })
  }
}

pub fn assign(buffer: Buffer) {
  use rebuild <- result.map(t.assign(buffer.projection))
  fn(new) { update_code(buffer, rebuild(e.Bind(new))) }
}

pub fn assign_before(buffer: Buffer) {
  use rebuild <- result.map(t.assign_before(buffer.projection))
  fn(new) { update_code(buffer, rebuild(e.Bind(new))) }
}

pub fn insert_variable(buffer: Buffer) {
  use rebuild <- result.map(t.variable(buffer.projection))
  fn(new) { update_code(buffer, rebuild(new)) }
}

pub fn insert_function(buffer: Buffer) {
  use rebuild <- result.map(t.function(buffer.projection))
  fn(new) { update_code(buffer, rebuild(new)) }
}

pub fn call_once(buffer: Buffer) {
  use new <- result.map(t.call(buffer.projection))
  update_code(buffer, new)
}

pub fn call_many(buffer: Buffer) {
  use rebuild <- result.map(t.call_many(buffer.projection))
  fn(count) { update_code(buffer, rebuild(count)) }
}

pub fn call_with(buffer: Buffer) {
  use new <- result.map(t.call_with(buffer.projection))
  update_code(buffer, new)
}

pub fn source(buffer: Buffer) {
  buffer.projection
  |> p.rebuild
  |> e.to_annotated([])
}

// maybe this should be copy_focus
pub fn copy_source(buffer: Buffer) {
  case buffer.projection {
    #(p.Exp(expression), _) ->
      e.to_annotated(expression, [])
      |> dag_json.to_string
      |> Ok
    _ -> Error(Nil)
  }
}

pub fn insert_integer(buffer: Buffer) {
  use #(value, rebuild) <- result.map(t.integer(buffer.projection))
  #(value, fn(new) { update_code(buffer, rebuild(new)) })
}

pub fn insert_string(buffer: Buffer) {
  use #(value, rebuild) <- result.map(t.string(buffer.projection))
  #(value, fn(new) { update_code(buffer, rebuild(new)) })
}

pub fn insert_binary(buffer: Buffer) {
  use rebuild <- result.map(set_expression(buffer))
  rebuild(e.Binary(<<>>))
}

pub fn create_list(buffer: Buffer) {
  use new <- result.map(t.list(buffer.projection))
  update_code(buffer, new)
}

pub fn create_empty_list(buffer: Buffer) {
  case buffer.projection {
    #(p.Exp(_old), zoom) -> {
      let new = #(p.Exp(e.List([], None)), zoom)
      Ok(update_code(buffer, new))
    }
    _ -> Error(Nil)
  }
}

pub fn spread(buffer: Buffer) {
  use new <- result.map(t.make_extensible(buffer.projection))
  update_code(buffer, new)
}

pub fn create_record(buffer: Buffer) {
  use rebuild <- result.map(t.record(buffer.projection))
  fn(new) { update_code(buffer, rebuild(new)) }
}

pub fn create_empty_record(buffer: Buffer) {
  use rebuild <- result.map(set_expression(buffer))
  rebuild(e.Record([], None))
}

pub fn overwrite(buffer: Buffer) {
  use rebuild <- result.map(t.overwrite(buffer.projection))
  fn(new) { update_code(buffer, rebuild(new)) }
}

pub fn select_field(buffer: Buffer) {
  use rebuild <- result.map(t.select_field(buffer.projection))
  fn(new) { update_code(buffer, rebuild(new)) }
}

pub fn tag(buffer: Buffer) {
  use rebuild <- result.map(t.tag(buffer.projection))
  fn(new) { update_code(buffer, rebuild(new)) }
}

pub fn match(buffer: Buffer) {
  use rebuild <- result.map(t.insert_match(buffer.projection))
  fn(new) { update_code(buffer, rebuild(new)) }
}

pub fn perform(buffer: Buffer) {
  use rebuild <- result.map(t.perform(buffer.projection))
  fn(new) { update_code(buffer, rebuild(new)) }
}

pub fn insert_handle(buffer: Buffer) {
  use rebuild <- result.map(t.handle(buffer.projection))
  fn(new) { update_code(buffer, rebuild(new)) }
}

pub fn insert_builtin(buffer: Buffer) {
  use #(_, rebuild) <- result.map(t.builtin(buffer.projection))
  fn(new) { update_code(buffer, rebuild(new)) }
}

pub fn insert_reference(buffer: Buffer) {
  use #(_, rebuild) <- result.map(t.insert_reference(buffer.projection))
  fn(new) { update_code(buffer, rebuild(new)) }
}

pub fn insert_release(buffer: Buffer) {
  use #(_, rebuild) <- result.map(t.insert_release(buffer.projection))
  fn(new) { update_code(buffer, rebuild(new)) }
}

pub fn insert_explicit_reference(buffer: Buffer) {
  use #(_, rebuild) <- result.map(t.insert_explicit_reference(buffer.projection))
  fn(new) { update_code(buffer, rebuild(new)) }
}

pub fn delete(buffer: Buffer) {
  use new <- result.map(t.delete(buffer.projection))
  update_code(buffer, new)
}
