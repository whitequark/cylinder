open OUnit2

let (>>=) = Lwt.(>>=)
let run f ctxt = Lwt_main.run (f ctxt)

let test_digest_to_string ctxt =
  let digest = `Inline, "the quick brown fox" in
  assert_equal ~printer:(fun x -> x)
               "inline:dGhlIHF1aWNrIGJyb3duIGZveA" (Block.digest_to_string digest);
  let digest = `SHA512, "\x07\xe5\x47\xd9\x58\x6f\x6a\x73\xf7\x3f\xba" ^
                        "\xc0\x43\x5e\xd7\x69\x51\x21\x8f\xb7\xd0\xc8\xd7\x88" ^
                        "\xa3\x09\xd7\x85\x43\x6b\xbb\x64\x2e\x93\xa2\x52\xa9" ^
                        "\x54\xf2\x39\x12\x54\x7d\x1e\x8a\x3b\x5e\xd6\xe1\xbf" ^
                        "\xd7\x09\x78\x21\x23\x3f\xa0\x53\x8f\x3d\xb8\x54\xfe\xe6" in
  assert_equal ~printer:(fun x -> x)
               ("sha512:B-VH2VhvanP3P7rAQ17XaVEhj7fQyNeIownXhU" ^
                "Nru2Quk6JSqVTyORJUfR6KO17W4b_XCXghIz-gU489uFT-5g") (Block.digest_to_string digest)

let test_digest_of_string ctxt =
  let printer x =
    match x with
    | Some x -> Printf.sprintf "Some %s" (Block.digest_to_string x)
    | None   -> "None"
  in
  assert_equal ~printer (Some (`Inline, "the quick brown fox"))
               (Block.digest_of_string "inline:dGhlIHF1aWNrIGJyb3duIGZveA");
  assert_equal ~printer (Some (`SHA512, "\x07\xe5\x47\xd9\x58\x6f\x6a\x73\xf7\x3f\xba" ^
                                "\xc0\x43\x5e\xd7\x69\x51\x21\x8f\xb7\xd0\xc8\xd7\x88" ^
                                "\xa3\x09\xd7\x85\x43\x6b\xbb\x64\x2e\x93\xa2\x52\xa9" ^
                                "\x54\xf2\x39\x12\x54\x7d\x1e\x8a\x3b\x5e\xd6\xe1\xbf" ^
                                "\xd7\x09\x78\x21\x23\x3f\xa0\x53\x8f\x3d\xb8\x54\xfe\xe6"))
               (Block.digest_of_string ("sha512:B-VH2VhvanP3P7rAQ17XaVEhj7fQyNeIownXhU" ^
                                        "Nru2Quk6JSqVTyORJUfR6KO17W4b_XCXghIz-gU489uFT-5g"));
  assert_equal ~printer None (Block.digest_of_string "inline:@#$@#$%#");
  assert_equal ~printer None (Block.digest_of_string "foobar:dGhl");
  assert_equal ~printer None (Block.digest_of_string "sha512:dGhl")

let test_digest_constr ctxt =
  assert_equal ~printer:Block.digest_to_string
               (`Inline, "the quick brown fox") (Block.digest_bytes "the quick brown fox");
  assert_equal ~printer:Block.digest_to_string
               (`SHA512, "\x94\x59\x16\x4c\x6b\x4a\x58\xf4\x6a\x4f\x4b\xc0\x81\x33\xa5\xb9" ^
                         "\xc6\xb5\x0c\xa6\x9e\x14\x6a\xd1\x9b\x6d\x10\xf3\xe2\xb2\xd9\x6b" ^
                         "\x57\x52\x21\xed\x8f\x7d\xed\xc3\x90\xa1\x96\x50\xce\xbe\x59\xf7" ^
                         "\x6f\x7d\x60\xf1\x05\xe6\x91\xeb\xdc\x14\x37\x6e\xbb\x15\xe2\xb0")
               (Block.digest_bytes (Bytes.make 64 'A'))

module In_memory_server = Block.Server(In_memory_store)

let setup ctxt =
  let backend = In_memory_store.create () in
  let sctx    = ZMQ.Context.create () in
  let sserver = ZMQ.Socket.create sctx ZMQ.Socket.router in
  ZMQ.Socket.bind sserver "tcp://127.0.0.1:5555";
  let server  = In_memory_server.create backend sserver in
  Lwt.async (fun () ->
    try%lwt In_memory_server.listen server
    with Unix.Unix_error(Unix.ENOTSOCK, _, _) -> Lwt.return_unit);
  let sclient = ZMQ.Socket.create sctx ZMQ.Socket.req in
  ZMQ.Socket.connect sclient "tcp://127.0.0.1:5555";
  let client  = Block.Client.create sclient in
  (backend, sctx, server, client)

let teardown (backend, sctx, server, client) ctxt =
  ZMQ.Socket.close (In_memory_server.to_socket server);
  ZMQ.Socket.close (Block.Client.to_socket client);
  ZMQ.Context.terminate sctx

let test_get_put ctxt =
  let (_backend, _sctx, _server, client) = bracket setup teardown ctxt in
  let data1   = Bytes.make 64 'A' in
  let digest1 = Block.digest_bytes data1 in
  let%lwt result = Block.Client.get client digest1 in
  assert_equal `Not_found result;
  let%lwt result = Block.Client.put client `SHA512 data1 in
  assert_equal `Ok result;
  let%lwt result = Block.Client.get client digest1 in
  assert_equal (`Ok data1) result;
  Lwt.return_unit

let test_erase ctxt =
  let (_backend, _sctx, _server, client) = bracket setup teardown ctxt in
  let data1   = Bytes.make 64 'A' in
  let digest1 = Block.digest_bytes data1 in
  Block.Client.put client `SHA512 data1 >>= fun _ ->
  let%lwt result = Block.Client.erase client digest1 in
  assert_equal `Ok result;
  let%lwt result = Block.Client.get client digest1 in
  assert_equal `Not_found result;
  Lwt.return_unit

let put_stuff client =
  let data1   = Bytes.make 64 'A' in
  let digest1 = Block.digest_bytes data1 in
  let data2   = Bytes.make 64 'B' in
  let digest2 = Block.digest_bytes data2 in
  Block.Client.put client `SHA512 data1 >>= fun _ ->
  Block.Client.put client `SHA512 data2 >>= fun _ ->
  Lwt.return (digest1, digest2)

let test_enumerate ctxt =
  let (_backend, _sctx, _server, client) = bracket setup teardown ctxt in
  let%lwt (digest1, digest2) = put_stuff client in
  match%lwt Block.Client.enumerate client "" with
  | `Ok (cookie, digests) ->
    let printer lst = String.concat "; " (List.map Block.digest_to_string digests) in
    assert_equal ~printer (ExtList.List.sort [digest1; digest2]) (ExtList.List.sort digests);
    Lwt.return_unit
  | _ -> assert_failure "Broken Block.Client.enumerate"

let test_digests ctxt =
  let (_backend, _sctx, _server, client) = bracket setup teardown ctxt in
  let%lwt (digest1, digest2) = put_stuff client in
  match%lwt Block.Client.digests client with
  | `Ok stream ->
    let%lwt lst = Lwt_stream.to_list stream in
    let printer lst = String.concat "; " (List.map Block.digest_to_string lst) in
    assert_equal ~printer (ExtList.List.sort [digest1; digest2]) (ExtList.List.sort lst);
    Lwt.return_unit
  | _ -> assert_failure "Broken Block.Client.digests"

let suite = "Test Block" >::: [
    "test_digest_of_string" >:: test_digest_of_string;
    "test_digest_to_string" >:: test_digest_to_string;
    "test_digest_constr"    >:: test_digest_constr;
    "test_get_put"          >:: run test_get_put;
    "test_erase"            >:: run test_erase;
    "test_enumerate"        >:: run test_enumerate;
    "test_digests"          >:: run test_digests;
  ]
