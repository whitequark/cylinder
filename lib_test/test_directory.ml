open OUnit2

let (>>=) = Lwt.(>>=)
let run f ctxt = Lwt_main.run (f ctxt)

let test_graph_elt ctxt =
  let (server_secret, server_public) = Box.random_key_pair () in
  let ckpoint_key = Secret_box.random_key () in
  let encoder = Graph.element_to_protobuf
                    (Secret_box.box_to_protobuf Directory.directory_to_protobuf) in

  let inner        = [] in
  let inner_elt    = Directory.directory_to_graph_elt
                        ~server:server_public ~key:ckpoint_key inner in
  let inner_digest = Block.digest_bytes (Protobuf.Encoder.encode_exn encoder inner_elt) in

  let dir          = [Directory.{ name = "foo"; kind = `Directory; content = inner_digest }] in
  let graph_elt    = Directory.directory_to_graph_elt
                        ~server:server_public ~key:ckpoint_key dir in

  let dir'         = Directory.directory_of_graph_elt ~key:ckpoint_key graph_elt in
  assert_equal (Some dir) dir';
  let edges        = Graph.edge_list ~server:server_secret graph_elt in
  assert_equal (Some [inner_digest]) edges;

  Lwt.return_unit

let suite = "Test Directory" >::: [
    "test_graph_elt" >:: run test_graph_elt;
  ]
