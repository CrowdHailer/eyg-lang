/// `Dynamic` data is data that we don't know the type of yet.
/// We likely get data like this from interop with Erlang, or from
/// IO with the outside world.
pub external type Dynamic

pub external fn from(anything) -> Dynamic =
  "../eyg_utils.js" "identity"
