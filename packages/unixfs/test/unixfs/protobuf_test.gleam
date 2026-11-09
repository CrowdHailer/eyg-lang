import unixfs/protobuf

pub fn round_trip_test() {
  let assert Ok(field1) = protobuf.varint_field(1, 1)
  let assert Ok(field2) = protobuf.bytes_field(2, <<"abc">>)

  assert Ok([#(1, protobuf.Varint(1)), #(2, protobuf.Bytes(<<"abc">>))])
    == protobuf.decode(<<field1:bits, field2:bits>>)
}
