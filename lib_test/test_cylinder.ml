open OUnit2

let suite = "Test Cylinder" >::: [
    Test_secret_box.suite;
    Test_box.suite;
    Test_backends.suite;
    Test_block.suite;
    Test_chunk.suite;
    Test_graph.suite;
    Test_file.suite;
  ]

let _ =
  run_test_tt_main suite
