// TODO fix proper action or add event listener
@external(javascript, "../../plinth_ffi.mjs", "onClick")
pub fn on_click(a: fn(String) -> Nil) -> Nil

@external(javascript, "../../plinth_ffi.mjs", "onKeyDown")
pub fn on_keydown(a: fn(String) -> Nil) -> Nil

@external(javascript, "../../plinth_ffi.mjs", "onChange")
pub fn on_change(a: fn(String) -> Nil) -> Nil
