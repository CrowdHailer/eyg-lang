/// A platform independent keypair container,
pub type Keypair(private, public) {
  Keypair(key_id: String, private_key: private, public_key: public)
}
