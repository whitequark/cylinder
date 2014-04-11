open OUnit2

let suite = "Test Cylinder" >::: [
    Test_block.suite;
  ]

let _ =
  run_test_tt_main suite
