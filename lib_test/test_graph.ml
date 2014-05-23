open OUnit2

let (>>=) = Lwt.(>>=)
let run f ctxt = Lwt_main.run (f ctxt)

let test_file_shadow ctxt =
  let _, _, _, client = Helper.blockserver_bracket ctxt in
  let%lwt capa, _ =
    Chunk.capability_of_data ~encoder:Data.data_to_protobuf ~convergence:""
                             (Data.data_of_bytes (Bytes.make 1024 'A')) in
  let file = File.{
    executable    = false;
    last_modified = Timestamp.now ();
    chunks        = [capa] } in
  let%lwt file_capa = Helper.put_chunk ~encoder:File.file_to_protobuf client file in
  let shadow = Graph.{
    children = [];
    blocks   = [Option.get (Chunk.capability_digest capa)] } in
  match%lwt Graph.file_shadow ~convergence:"" ~client file_capa with
  | `Ok shadow_capa ->
    let%lwt shadow' = Helper.get_chunk ~decoder:Graph.shadow_from_protobuf client shadow_capa in
    assert_equal shadow shadow';
    Lwt.return_unit
  | _ -> assert_failure "Graph.file_shadow"

let suite = "Test Graph" >::: [
    "test_file_shadow" >:: run test_file_shadow;
  ]
