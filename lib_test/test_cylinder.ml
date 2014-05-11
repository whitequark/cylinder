open OUnit2

let suite = "Test Cylinder" >::: [
    Test_block.suite;
    Test_backends.suite;
  ]

let _ =
  run_test_tt_main suite
