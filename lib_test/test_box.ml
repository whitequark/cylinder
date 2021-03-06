open OUnit2

let test_roundtrip_keys ctxt =
  let sk, pk = Box.random_key_pair () in
  let sbytes = Protobuf.Encoder.encode_exn Box.secret_key_to_protobuf sk in
  let sk'    = Protobuf.Decoder.decode_exn Box.secret_key_from_protobuf sbytes in
  assert_equal sk sk';
  let pbytes = Protobuf.Encoder.encode_exn Box.public_key_to_protobuf pk in
  let pk'    = Protobuf.Decoder.decode_exn Box.public_key_from_protobuf pbytes in
  assert_equal pk pk'

type message = string [@@deriving protobuf]

let test_roundclear_clear ctxt =
  let msg        = "wild wild fox" in
  let sk,  pk    = Box.random_key_pair () in
  let sk', pk'   = Box.random_key_pair () in
  let box        = Box.store msg sk pk' in
  let msg'       = Box.decrypt box sk' pk in
  assert_equal (Some msg) msg'

let test_roundclear_mismatch ctxt =
  let msg        = "wild wild fox" in
  let sk,   pk   = Box.random_key_pair () in
  let sk',  pk'  = Box.random_key_pair () in
  let box        = Box.store msg sk pk' in
  let sk'', pk'' = Box.random_key_pair () in
  let msg'       = Box.decrypt box sk' pk'' in
  Option.may (Printf.eprintf "\n%s\n%!") msg';
  assert_equal None msg'

let test_roundtrip ctxt =
  let msg        = "wild wild fox" in
  let sk,   pk   = Box.random_key_pair () in
  let sk',  pk'  = Box.random_key_pair () in
  let box        = Box.store msg sk pk' in
  let bytes      = Protobuf.Encoder.encode_exn
                       (Box.box_to_protobuf message_to_protobuf) box in
  let box'       = Protobuf.Decoder.decode_exn
                       (Box.box_from_protobuf message_from_protobuf) bytes in
  let msg'       = Box.decrypt box' sk' pk in
  assert_equal (Some msg) msg'

let test_roundtrip_mismatch ctxt =
  let msg        = "wild wild fox" in
  let sk,   pk   = Box.random_key_pair () in
  let sk',  pk'  = Box.random_key_pair () in
  let box        = Box.store msg sk pk' in
  let bytes      = Protobuf.Encoder.encode_exn
                       (Box.box_to_protobuf message_to_protobuf) box in
  let box'       = Protobuf.Decoder.decode_exn
                       (Box.box_from_protobuf message_from_protobuf) bytes in
  let sk'', pk'' = Box.random_key_pair () in
  let msg'       = Box.decrypt box' sk' pk'' in
  assert_equal None msg'

let suite = "Test Box" >::: [
    "test_roundtrip_keys"      >:: test_roundtrip_keys;
    "test_roundclear"          >:: test_roundclear_clear;
    "test_roundclear_mismatch" >:: test_roundclear_mismatch;
    "test_roundtrip"           >:: test_roundtrip;
    "test_roundtrip_mismatch"  >:: test_roundtrip_mismatch;
  ]
