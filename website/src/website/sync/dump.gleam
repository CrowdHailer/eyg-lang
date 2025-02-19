import gleam/dict.{type Dict}
import website/sync/supabase

pub type Dump {
  Dump(
    registry: Dict(String, String),
    packages: Dict(String, Dict(Int, supabase.Release)),
    fragments: List(supabase.Fragment),
  )
}
