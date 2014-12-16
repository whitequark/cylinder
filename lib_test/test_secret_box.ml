open OUnit2

let test_roundtrip_key ctxt =
  let key   = Secret_box.random_key () in
  let bytes = Protobuf.Encoder.encode_exn Secret_box.key_to_protobuf key in
  let key'  = Protobuf.Decoder.decode_exn Secret_box.key_from_protobuf bytes in
  assert_equal key key'

type message = string [@@deriving protobuf]

let test_roundclear_clear ctxt =
  let msg  = "wild wild fox" in
  let key  = Secret_box.random_key () in
  let box  = Secret_box.store msg key in
  let msg' = Secret_box.decrypt box key in
  assert_equal (Some msg) msg'

let test_roundclear_mismatch ctxt =
  let msg  = "wild wild fox" in
  let key  = Secret_box.random_key () in
  let box  = Secret_box.store msg key in
  let key' = Secret_box.random_key () in
  let msg' = Secret_box.decrypt box key' in
  assert_equal None msg'

let test_roundtrip ctxt =
  let msg   = "wild wild fox" in
  let key   = Secret_box.random_key () in
  let box   = Secret_box.store msg key in
  let bytes = Protobuf.Encoder.encode_exn
                  (Secret_box.box_to_protobuf message_to_protobuf) box in
  let box'  = Protobuf.Decoder.decode_exn
                  (Secret_box.box_from_protobuf message_from_protobuf) bytes in
  let msg'  = Secret_box.decrypt box' key in
  assert_equal (Some msg) msg'

let test_roundtrip_mismatch ctxt =
  let msg   = "wild wild fox" in
  let key   = Secret_box.random_key () in
  let box   = Secret_box.store msg key in
  let bytes = Protobuf.Encoder.encode_exn
                  (Secret_box.box_to_protobuf message_to_protobuf) box in
  let box'  = Protobuf.Decoder.decode_exn
                  (Secret_box.box_from_protobuf message_from_protobuf) bytes in
  let key'  = Secret_box.random_key () in
  let msg'  = Secret_box.decrypt box' key' in
  assert_equal None msg'

let suite = "Test Secret_box" >::: [
    "test_roundtrip_key"       >:: test_roundtrip_key;
    "test_roundclear"          >:: test_roundclear_clear;
    "test_roundclear_mismatch" >:: test_roundclear_mismatch;
    "test_roundtrip"           >:: test_roundtrip;
    "test_roundtrip_mismatch"  >:: test_roundtrip_mismatch;
  ]
