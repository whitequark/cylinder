open OUnit2

let (>>=) = Lwt.(>>=)
let run f ctxt = Lwt_main.run (f ctxt)

let test_file_shadow ctxt =
  let%lwt capa, _ =
    Chunk.capability_of_data ~encoder:Data.data_to_protobuf ~convergence:""
                             (Data.data_of_bytes (Bytes.make 1024 'A')) in
  let file = File.{
    executable    = false;
    last_modified = Timestamp.now ();
    chunks        = [capa] } in
  let shadow = Graph.{
    children = [];
    blocks   = [Option.get (Chunk.capability_digest capa)] } in
  assert_equal shadow (Graph.file_shadow file);
  Lwt.return_unit

let suite = "Test Graph" >::: [
    "test_file_shadow" >:: run test_file_shadow;
  ]
