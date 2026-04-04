//// Code for generating keys and signing messages.
//// 
//// This library uses data types defined in the untethered package.

import kryptos/eddsa
import multiformats/base32
import untethered/keypair.{Keypair}

/// generate an Ed22519 keypair
pub fn generate_key() {
  let #(private_key, public_key) = eddsa.generate_key_pair(eddsa.Ed25519)
  let assert Ok(exported) = eddsa.public_key_to_der(public_key)
  let key_id = base32.encode(exported)
  Keypair(key_id:, private_key:, public_key:)
}

pub fn sign(payload, keypair) {
  let Keypair(private_key:, ..) = keypair
  eddsa.sign(private_key, payload)
  |> base32.encode
}

pub fn verify(bytes, key_id, signature) {
  let key_id = base32.decode(key_id)
  let assert Ok(public_key) = eddsa.public_key_from_der(key_id)
  let signature = base32.decode(signature)

  case eddsa.verify(public_key, bytes, signature:) {
    True -> Ok(Nil)
    False -> Error(Nil)
  }
}
