open OUnit2

let (>>=) = Lwt.(>>=)
let run f ctxt = Lwt_main.run (f ctxt)

type message = string [@@protobuf]

let data    = "wild wild fox"
let dataL   = String.make 128 'A'
let bytes   = Protobuf.Encoder.encode_exn message_to_protobuf data
let bytesL  = Protobuf.Encoder.encode_exn message_to_protobuf dataL
let decoder = message_from_protobuf
let encoder = message_to_protobuf
let printer = Chunk.inspect_capability

let test_capa_inline ctxt =
  let%lwt capa, blk = Chunk.capability_of_data ~encoder ~convergence:"" data in
  assert_equal ~printer (Chunk.Inline bytes) capa;
  assert_equal None blk;
  Lwt.return_unit

let test_capa_encrypt ctxt =
  match%lwt Chunk.capability_of_data ~encoder ~convergence:"" dataL with
  | Chunk.Stored { Chunk.algorithm = `SHA512_XSalsa20_Poly1305;
                   digest = (`SHA512, digest_bytes); key }, Some enc_bytes ->
    assert_equal digest_bytes Sodium.Hash.Bytes.(of_hash (digest enc_bytes));
    let skey, snonce = Bytes.(sub key 0 32, sub key 32 24) in
    let skey, snonce = Sodium.Secret_box.Bytes.(to_key skey, to_nonce snonce) in
    assert_equal bytesL Sodium.Secret_box.Bytes.(secret_box_open skey enc_bytes snonce);
    Lwt.return_unit
  | _ -> assert_failure "Chunk.capability_of_data"

let test_capa_roundtrip ctxt =
  let%lwt capa, blk = Chunk.capability_of_data ~encoder ~convergence:"" dataL in
  let%lwt chunk'    = Chunk.capability_to_data ~decoder capa blk in
  assert_equal (`Ok dataL) chunk';
  Lwt.return_unit

let test_convergence_used ctxt =
  let%lwt capa,  blk  = Chunk.capability_of_data ~encoder ~convergence:"" dataL in
  let%lwt capa', blk' = Chunk.capability_of_data ~encoder ~convergence:"1" dataL in
  assert_bool "convergence used" (capa <> capa' && blk <> blk');
  Lwt.return_unit

let test_network_inline ctxt =
  let _, _, _, client = Helper.blockserver_bracket ctxt in
  match%lwt Chunk.store_data ~encoder ~convergence:"" client data with
  | `Ok capa ->
    begin match%lwt Chunk.retrieve_data ~decoder client capa with
    | `Ok data' ->
      assert_equal data data';
      Lwt.return_unit
    | _ -> assert_failure "Chunk.retrieve_data"
    end
  | _ -> assert_failure "Chunk.store_data"

let test_network_stored ctxt =
  let backend, _, _, client = Helper.blockserver_bracket ctxt in
  match%lwt Chunk.store_data ~encoder ~convergence:"" client dataL with
  | `Ok ((Chunk.Stored handle) as capa) ->
    begin match%lwt Chunk.retrieve_data ~decoder client capa with
    | `Ok dataL' ->
      assert_equal dataL dataL';
      Lwt.return_unit
    | _ -> assert_failure "Chunk.retrieve_data"
    end >>= fun () ->
    In_memory_store.erase backend handle.Chunk.digest >>= fun () ->
    begin match%lwt Chunk.retrieve_data ~decoder client capa with
    | `Not_found -> Lwt.return_unit
    | _ -> assert_failure "Chunk.retrieve_data"
    end
  | _ -> assert_failure "Chunk.store_data"

let suite = "Test Chunk" >::: [
    "test_capa_inline"      >:: run test_capa_inline;
    "test_capa_encrypt"     >:: run test_capa_encrypt;
    "test_capa_roundtrip"   >:: run test_capa_roundtrip;
    "test_convergence_used" >:: run test_convergence_used;
    "test_network_inline"   >:: run test_network_inline;
    "test_network_stored"   >:: run test_network_stored;
  ]
