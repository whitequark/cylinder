open OUnit2

let (>>=) = Lwt.(>>=)
let run f ctxt = Lwt_main.run (f ctxt)

let test_chunk_bytes_conv ctxt =
  let chunk = Chunk.chunk_of_bytes (Bytes.of_string "hello") in
  assert_equal `None chunk.Chunk.encoding;
  assert_equal "hello" chunk.Chunk.content;
  let bytes = Chunk.chunk_to_bytes chunk in
  assert_equal "hello" bytes

let test_capa_inline ctxt =
  let chunk = Chunk.chunk_of_bytes (Bytes.of_string "hello") in
  let bytes = Protobuf.Encoder.encode_exn Chunk.chunk_to_protobuf chunk in
  let%lwt capa, blk = Chunk.capability_of_chunk ~convergence:"" chunk in
  assert_equal (Chunk.Inline bytes) capa;
  assert_equal None blk;
  Lwt.return_unit

let test_capa_encrypt ctxt =
  let chunk = Chunk.chunk_of_bytes (Bytes.make 128 'A') in
  let bytes = Protobuf.Encoder.encode_exn Chunk.chunk_to_protobuf chunk in
  match%lwt Chunk.capability_of_chunk ~convergence:"" chunk with
  | Chunk.Stored { Chunk.algorithm = `SHA512_XSalsa20_Poly1305;
                   digest = (`SHA512, digest_bytes); key }, Some enc_bytes ->
    assert_equal digest_bytes Sodium.Hash.Bytes.(of_hash (digest enc_bytes));
    let skey, snonce = Bytes.(sub key 0 32, sub key 32 24) in
    let skey, snonce = Sodium.Secret_box.Bytes.(to_key skey, to_nonce snonce) in
    assert_equal bytes Sodium.Secret_box.Bytes.(secret_box_open skey enc_bytes snonce);
    Lwt.return_unit
  | _ -> assert_failure "Chunk.capability_of_chunk"

let test_capa_roundtrip ctxt =
  let chunk = Chunk.chunk_of_bytes (Bytes.make 128 'A') in
  let%lwt capa, blk = Chunk.capability_of_chunk ~convergence:"" chunk in
  let%lwt chunk'    = Chunk.capability_to_chunk capa blk in
  assert_equal (`Ok chunk) chunk';
  Lwt.return_unit

let test_convergence_used ctxt =
  let chunk = Chunk.chunk_of_bytes (Bytes.make 128 'A') in
  let%lwt capa,  blk  = Chunk.capability_of_chunk ~convergence:"" chunk in
  let%lwt capa', blk' = Chunk.capability_of_chunk ~convergence:"1" chunk in
  assert_bool "convergence used" (capa <> capa' && blk <> blk');
  Lwt.return_unit

let test_network_inline ctxt =
  let (_backend, _zctx, _server, client) = Helper.blockserver_bracket ctxt in
  let chunk = Chunk.chunk_of_bytes (Bytes.to_string "hello") in
  let%lwt capa, blk = Chunk.capability_of_chunk ~convergence:"" chunk in
  match capa with
  | Chunk.Inline _ ->
    let%lwt result = Chunk.store_chunk client (capa, blk) in
    assert_equal `Ok result;
    begin match%lwt Chunk.retrieve_chunk client capa with
    | `Ok chunk' ->
      assert_equal chunk chunk';
      Lwt.return_unit
    | _ -> assert_failure "Chunk.retrieve_chunk"
    end
  | _ -> assert_failure "Chunk.capability_of_chunk"

let test_network_stored ctxt =
  let (backend, _zctx, _server, client) = Helper.blockserver_bracket ctxt in
  let chunk = Chunk.chunk_of_bytes (Bytes.make 128 'A') in
  let%lwt capa, blk = Chunk.capability_of_chunk ~convergence:"" chunk in
  match capa with
  | Chunk.Stored handle ->
    let%lwt result = Chunk.store_chunk client (capa, blk) in
    assert_equal `Ok result;
    begin match%lwt Chunk.retrieve_chunk client capa with
    | `Ok chunk' ->
      assert_equal chunk chunk';
      Lwt.return_unit
    | _ -> assert_failure "Chunk.retrieve_chunk"
    end >>= fun () ->
    In_memory_store.erase backend handle.Chunk.digest >>= fun () ->
    begin match%lwt Chunk.retrieve_chunk client capa with
    | `Not_found -> Lwt.return_unit
    | _ -> assert_failure "Chunk.retrieve_chunk"
    end
  | _ -> assert_failure "Chunk.capability_of_chunk"

let suite = "Test Chunk" >::: [
    "test_chunk_bytes_conv" >:: test_chunk_bytes_conv;
    "test_capa_inline"      >:: run test_capa_inline;
    "test_capa_encrypt"     >:: run test_capa_encrypt;
    "test_capa_roundtrip"   >:: run test_capa_roundtrip;
    "test_convergence_used" >:: run test_convergence_used;
    "test_network_inline"   >:: run test_network_inline;
    "test_network_stored"   >:: run test_network_stored;
  ]
