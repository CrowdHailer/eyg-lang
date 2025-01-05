import eyg/sync/supabase
import eygir/expression as e
import gleam/dict.{type Dict}

pub type Dump {
  Dump(
    registry: Dict(String, String),
    packages: Dict(String, Dict(Int, supabase.Release)),
    fragments: Dict(String, e.Expression),
  )
}
