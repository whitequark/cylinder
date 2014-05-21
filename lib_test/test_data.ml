open OUnit2

let test_chunk_bytes_conv ctxt =
  let chunk = Data.data_of_bytes (Bytes.of_string "hello") in
  assert_equal `None chunk.Data.encoding;
  assert_equal "hello" chunk.Data.content;
  let bytes = Data.data_to_bytes chunk in
  assert_equal "hello" bytes

let suite = "Test Data" >::: [
    "test_chunk_bytes_conv" >:: test_chunk_bytes_conv;
  ]
