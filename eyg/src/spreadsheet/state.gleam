// maybe model or just spreadsheet is a better name

pub type State {
  State(frame: Frame, focus: #(Int, Int))
}


pub type Frame {
  Frame(headers: List(String), data: List(List(String)))
}


pub fn init() {
  State(
    Frame(
      ["Name", "Address", "Stuff"],
      [["Alice", "London", ""], ["Bob", "London", ""]],
    ),
    #(0, 0),
  )
}
