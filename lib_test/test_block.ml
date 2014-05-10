open OUnit2

let test_encrypt_decrypt ctxt =
  let message    = Lwt_bytes.of_string "the answer" in
  let key, block = Block.encrypt ~convergence:"42" message in
  let message'   = Block.decrypt (key, block) in
  assert_equal ~printer:Lwt_bytes.to_string message message'

let suite = "Test Block" >::: [
    "test_encrypt_decrypt" >:: test_encrypt_decrypt;
  ]
