// selection and ranges

pub type Selection

@external(javascript, "../../plinth_ffi.js", "getSelection")
pub fn get_selection() -> Result(Selection, Nil)

pub type Range

@external(javascript, "../../plinth_ffi.js", "getRangeAt")
pub fn get_range_at(a: Selection, b: Int) -> Result(Range, Nil)
