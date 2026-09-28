import kryptos/eddsa
import multiformats/base32
import untethered/keypair.{Keypair}

pub fn generate_key() {
  let #(private_key, public_key) = eddsa.generate_key_pair(eddsa.Ed25519)
  to_keypair(private_key, public_key)
}

pub fn sign(payload, keypair) {
  let Keypair(private_key:, ..) = keypair
  eddsa.sign(private_key, payload)
  |> base32.encode
}

pub fn to_keypair(
  private_key: eddsa.PrivateKey,
  public_key: eddsa.PublicKey,
) -> keypair.Keypair(eddsa.PrivateKey, eddsa.PublicKey) {
  let assert Ok(exported) = eddsa.public_key_to_der(public_key)
  let key_id = base32.encode(exported)
  Keypair(key_id:, private_key:, public_key:)
}
