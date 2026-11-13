# Native Nix adapter; graph acquisition and CID verification are Gleam CLI logic.
{ eyg, system ? builtins.currentSystem }:
{ reference, hash, hub ? "https://eyg.run", name ? "eyg-package" }:
builtins.derivation {
  inherit name system;
  builder = "${eyg}/bin/eyg";
  args = [ "fetch-package" reference (builtins.placeholder "out") ];
  EYG_ORIGIN = hub;
  HOME = "/homeless-shelter";
  outputHashAlgo = "sha256";
  outputHashMode = "flat";
  outputHash = hash;
  impureEnvVars = [ "http_proxy" "https_proxy" "all_proxy" "no_proxy" ];
}
