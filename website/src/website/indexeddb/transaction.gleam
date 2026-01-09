import website/indexeddb/object_store.{type ObjectStore}

pub type Transaction

@external(javascript, "../../indexeddb_ffi.mjs", "transaction_object_store")
pub fn object_store(
  transaction: Transaction,
  name: String,
) -> Result(ObjectStore, String)
