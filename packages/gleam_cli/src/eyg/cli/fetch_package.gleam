//// Materialise a pinned package closure as a portable bundle for Nix or EYG.

import eyg/cli/internal/config
import glasshouse/bundle
import loam/package
import loam/system

pub fn execute(
  reference: String,
  output: String,
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use acquired <- system.then(package.acquire(reference, config.client.origin))
  use acquired <- system.try(acquired)
  use written <- system.then(system.write_file(
    output,
    bundle.to_string(acquired),
  ))
  use Nil <- system.try(written)
  system.Done(Ok(0))
}
