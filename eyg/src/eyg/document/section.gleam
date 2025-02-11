import gleam/list
import morph/editable

pub type Section {
  Section(comments: List(String), snippet: editable.Assignments)
}

fn gather_sections(from, comments, assigns, sections) {
  case from, assigns {
    [], _ ->
      list.reverse([
        Section(list.reverse(comments), list.reverse(assigns)),
        ..sections
      ])
    // if assigns is empty keep adding comments
    [#(editable.Bind("_"), editable.String(comment)), ..from], [] ->
      gather_sections(from, [comment, ..comments], assigns, sections)
    // if assignes is not empty start new block
    [#(editable.Bind("_"), editable.String(comment)), ..from], _ -> {
      let comments = list.reverse(comments)
      let assigns = list.reverse(assigns)
      // comments are context
      let sections = [Section(comments, assigns), ..sections]
      gather_sections(from, [comment], [], sections)
    }
    [assign, ..from], _ ->
      gather_sections(from, comments, [assign, ..assigns], sections)
  }
}

pub fn from_expression(expression) {
  case editable.from_annotated(expression) {
    editable.Block(assigns, then, _open) -> {
      let assigns = editable.open_assignments(assigns)
      #(gather_sections(assigns, [], [], []), then)
    }
    other -> #([], other)
  }
}
