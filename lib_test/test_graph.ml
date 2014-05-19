open OUnit2

type message = string [@@protobuf]

let test_roundtrip ctxt =
  let server_secret, server_public = Box.random_key_pair () in
  let client_secret, client_public = Box.random_key_pair () in
  let edges   = [Block.digest_bytes (Bytes.of_string "foo")] in
  let elem    = Graph.element ~server:server_public ~updater:(client_secret, client_public)
                              edges "bar" in
  let bytes   = Protobuf.Encoder.encode_exn
                    (Graph.element_to_protobuf message_to_protobuf) elem in
  let elem'   = Protobuf.Decoder.decode_exn
                    (Graph.element_from_protobuf message_from_protobuf) bytes in
  assert_equal elem.Graph.content elem'.Graph.content;
  let edges'  = Graph.edge_list ~server:server_secret elem' in
  assert_equal (Some edges) edges'

let suite = "Test Graph" >::: [
    "test_roundtrip" >:: test_roundtrip;
  ]
