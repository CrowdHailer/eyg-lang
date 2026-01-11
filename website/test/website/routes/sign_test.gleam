import gleam/bit_array
import gleam/javascript/promise
import gleam/option.{None}
import indentity/server
import plinth/browser/crypto/subtle

pub fn create_key_test() {
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
  echo ks
  use exported <- promise.await(subtle.export(public, subtle.Spki))
  let assert Ok(exported) = exported
  exported
  let key = bit_array.base64_url_encode(exported, False)

  // Plinth uuid
  let entity = "abc123456"
  let signatory = server.Signatory(entity:, sequence: 0, key:)
  let entry =
    server.Entry(
      entity:,
      sequence: 1,
      previous: None,
      signatory:,
      content: server.AddKey(key),
    )
  let bytes = server.entry_bytes(entry)
  echo bytes
  use signature <- promise.await(subtle.sign(
    subtle.EcdsaParams(subtle.SHA256),
    private,
    bytes,
  ))
  let assert Ok(signature) = signature
  let signature = bit_array.base64_url_encode(signature, False)
  echo signature
  todo
}
