import eyg/sync/supabase
import gleam/dict.{type Dict}

pub type Dump {
  Dump(
    registry: Dict(String, String),
    packages: Dict(String, Dict(Int, supabase.Release)),
    fragments: List(supabase.Fragment),
  )
}
