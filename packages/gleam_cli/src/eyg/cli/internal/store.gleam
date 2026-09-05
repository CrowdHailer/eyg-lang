import eyg/cli/internal/crypto
import eyg/cli/internal/platform
import eyg/cli/system
import eyg/hub/schema
import filepath
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import kryptos/eddsa
import multiformats/cid/v1
import simplifile
import untethered/keypair

pub type Signatory {
  Signatory(
    alias: String,
    principal: v1.Cid,
    keypair: keypair.Keypair(eddsa.PrivateKey, eddsa.PublicKey),
  )
}

pub fn save_signatory(
  signatory: Signatory,
  dirs: platform.PlatformDirs,
) -> system.Effect(Result(Nil, String)) {
  let Signatory(alias:, principal:, keypair:) = signatory

  let path = signatories_dir(dirs) <> alias <> ".json"
  use created <- system.then(
    system.create_directory(filepath.directory_name(path)),
  )
  use Nil <- system.try(created)
  let blob =
    signatory_encode(principal, keypair)
    |> json.to_string

  use written <- system.then(system.write_file(path, blob))
  use Nil <- system.try(written)

  // The file embeds a private key — restrict it to the owner (rw-------).
  system.set_permissions(path, 0o600)
}

pub fn all_signatories(dirs) {
  use paths <- result.try(
    simplifile.get_files(signatories_dir(dirs))
    |> result.map_error(simplifile.describe_error),
  )

  list.try_map(paths, fn(path) {
    use encoded <- result.try(
      simplifile.read(path) |> result.map_error(simplifile.describe_error),
    )
    let alias =
      filepath.base_name(path)
      |> filepath.strip_extension
    let assert Ok(#(principal, keypair)) =
      json.parse(encoded, signatory_decoder())
    Ok(Signatory(alias:, principal:, keypair:))
  })
}

fn signatory_decoder() -> decode.Decoder(_) {
  use principal <- decode.field("principal", schema.cid_decoder())
  use keypair <- decode.field("keypair", keypair_decoder())
  decode.success(#(principal, keypair))
}

fn signatory_encode(principal, keypair) {
  json.object([
    #("principal", json.string(v1.to_string(principal))),
    #("keypair", keypair_encode(keypair)),
  ])
}

fn keypair_decoder() {
  use encoded <- decode.then(decode.string)
  case eddsa.from_pem(encoded) {
    Ok(#(private_key, public_key)) ->
      decode.success(crypto.to_keypair(private_key, public_key))
    Error(Nil) -> decode.failure(crypto.generate_key(), "keypair")
  }
}

fn keypair_encode(keypair: keypair.Keypair(eddsa.PrivateKey, _)) {
  let assert Ok(encoded) = eddsa.to_pem(keypair.private_key)
  json.string(encoded)
}

fn signatories_dir(dirs: platform.PlatformDirs) -> String {
  let platform.PlatformDirs(config_dir:, ..) = dirs
  config_dir <> "/eyg/signatories/"
}
