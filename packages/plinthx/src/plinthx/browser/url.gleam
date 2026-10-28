//// URL object lifetime: https://url.spec.whatwg.org/

@external(javascript, "./url_ffi.mjs", "revokeObjectURL")
pub fn revoke_object_url(url: String) -> Nil
