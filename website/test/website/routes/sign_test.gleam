import gleam/bit_array
import gleam/javascript/promise
import gleam/option.{None}
import indentity/server
import kryptos/ec
import kryptos/ecdsa
import kryptos/eddsa
import kryptos/hash
import plinth/browser/crypto/subtle

// You might also see these as PEM files, which are just base64-encoded DER with header/footer lines like -----BEGIN PRIVATE KEY----- (PKCS#8) or -----BEGIN PUBLIC KEY----- (SPKI).

pub fn ed25519_test() {
  use ks <- promise.await(
    subtle.generate_key(subtle.Ed25519GenParams, False, [
      subtle.Sign,
      subtle.Verify,
    ]),
  )
  let assert Ok(#(public, private)) = ks
  let message = <<"eddy test">>
  use signature <- promise.await(subtle.sign(subtle.Ed25519, private, message))
  let assert Ok(signature) = signature

  use exported <- promise.await(subtle.export(public, subtle.Spki))
  let assert Ok(exported) = exported
  echo "-----------"
  echo exported
  echo signature
  let assert Ok(pub_) = eddsa.public_key_from_der(exported)
  echo eddsa.verify(pub_, message, signature:)
  todo
}

pub fn create_key() {
  todo
  use ks <- promise.await(
    subtle.generate_key(
      subtle.EcKeyGenParams(name: "ECDSA", named_curve: "P-256"),
      False,
      [
        subtle.Sign,
        subtle.Verify,
      ],
    ),
  )
  let assert Ok(#(public, private)) = ks

  use exported <- promise.await(subtle.export(public, subtle.Spki))
  let assert Ok(exported) = exported

  let assert Ok(public_key) =
    ec.public_key_from_der(exported)
    |> echo
  let message = <<"hello">>
  use signature <- promise.await(subtle.sign(
    subtle.EcdsaParams(subtle.SHA256),
    private,
    message,
  ))
  let assert Ok(signature) = signature
  ecdsa.verify(public_key, message, signature, hash.Sha256)
  |> echo
  todo
  // exported
  // let key = bit_array.base64_url_encode(exported, False)

  // // Plinth uuid
  // let entity = "abc123456"
  // let signatory = server.Signatory(entity:, sequence: 0, key:)
  // let entry =
  //   server.Entry(
  //     entity:,
  //     sequence: 1,
  //     previous: None,
  //     signatory:,
  //     content: server.AddKey(key),
  //   )
  // let bytes = server.entry_bytes(entry)
  // echo bytes
  // let assert Ok(signature) = signature
  // let signature = bit_array.base64_url_encode(signature, False)
  // echo signature
  // todo
}
