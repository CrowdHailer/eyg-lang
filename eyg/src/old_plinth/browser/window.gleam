@external(javascript, "../../plinth_ffi.js", "addEventListener")
pub fn add_event_listener(a: String, b: fn(Nil) -> Nil) -> Nil

@external(javascript, "../../plinth_ffi.js", "encodeURI")
pub fn encode_uri(a: String) -> String

@external(javascript, "../../plinth_ffi.js", "decodeURI")
pub fn decode_uri(a: String) -> String

@external(javascript, "../../plinth_ffi.js", "decodeURIComponent")
pub fn decode_uri_component(a: String) -> String

// Not sure it's worth returning location as a Gleam URL because all  components are optional
// however page must have an origin/protocol but it might be file based.
// Nice having a simple location effect in eyg

@external(javascript, "../../plinth_ffi.js", "locationSearch")
pub fn location_search() -> Result(String, Nil)

// selection and ranges

pub type Selection

@external(javascript, "../../plinth_ffi.js", "getSelection")
pub fn get_selection() -> Result(Selection, Nil)

pub type Range

@external(javascript, "../../plinth_ffi.js", "getRangeAt")
pub fn get_range_at(a: Selection, b: Int) -> Result(Range, Nil)
