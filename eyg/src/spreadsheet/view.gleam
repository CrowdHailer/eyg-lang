import spreadsheet/state
import spreadsheet/view/dataframe

pub fn render(state: state.State) {
  let #(_, x, y) = state.focus
  dataframe.render(state.frame(state), #(x, y))
}
