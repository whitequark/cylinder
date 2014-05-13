open OUnit2

let suite = "Test Cylinder" >::: [
    Test_backends.suite;
    Test_block.suite;
    Test_chunk.suite;
  ]

let _ =
  run_test_tt_main suite
