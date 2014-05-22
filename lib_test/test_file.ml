open OUnit2

let (>>=) = Lwt.(>>=)
let run f ctxt = Lwt_main.run (f ctxt)

let test_create_inline ctxt =
  let _, _, _, client = Helper.blockserver_bracket ctxt in
  let%lwt fd = Helper.tmpdata_bracket ctxt "hello" in
  match%lwt File.create_from_unix_fd ~convergence:"" ~client fd with
  | `Ok file_capa ->
    let%lwt file = Helper.get_chunk ~decoder:File.file_from_protobuf client file_capa in
    let%lwt stat = Lwt_unix.fstat fd in
    assert_equal File.{
      executable    = false;
      chunks        = [Chunk.Inline "\x7a\x05hello"];
      last_modified = Timestamp.of_unix_time (stat.Lwt_unix.st_mtime);
    } file;
    Lwt.return_unit
  | _ -> assert_failure "File.create_from_unix_fd"

let test_update_inline ctxt =
  let _, _, _, client = Helper.blockserver_bracket ctxt in
  let origin = File.{
      executable    = false;
      last_modified = Timestamp.now ();
      chunks        = [Chunk.Inline "\x7a\x05hello";
                       Chunk.Inline "\x7a\x03foo";
                       Chunk.Inline "\x7a\x03bar";] }
  in
  let%lwt origin_capa = Helper.put_chunk ~encoder:File.file_to_protobuf client origin in
  let%lwt fd = Helper.tmpdata_bracket ctxt "hellobazbar" in
  begin match%lwt File.update_with_unix_fd ~convergence:"" ~client origin_capa fd with
  | `Ok file_capa' ->
    let%lwt file' = Helper.get_chunk ~decoder:File.file_from_protobuf client file_capa' in
    assert_equal [Chunk.Inline "\x7a\x05hello";
                  Chunk.Inline "\x7a\x03baz";
                  Chunk.Inline "\x7a\x03bar";]
                 (file'.File.chunks);
    Lwt.return_unit
  | _ -> assert_failure "File.update_with_unix_fd"
  end >>= fun () ->
  let%lwt fd = Helper.tmpdata_bracket ctxt "helloHI" in
  begin match%lwt File.update_with_unix_fd ~convergence:"" ~client origin_capa fd with
  | `Ok file_capa' ->
    let%lwt file' = Helper.get_chunk ~decoder:File.file_from_protobuf client file_capa' in
    assert_equal [Chunk.Inline "\x7a\x05hello";
                  Chunk.Inline "\x7a\x02HI";]
                 (file'.File.chunks);
    Lwt.return_unit
  | _ -> assert_failure "File.update_with_unix_fd"
  end

let test_roundtrip ctxt =
  let _, _, _, client = Helper.blockserver_bracket ctxt in
  let roundtrip data =
    let%lwt fd = Helper.tmpdata_bracket ctxt data in
    begin match%lwt File.create_from_unix_fd ~convergence:"" ~client fd with
    | `Ok capa -> Lwt.return capa | _ -> assert_failure "File.create_from_unix_fd"
    end >>= fun capa ->

    let%lwt fd' = Helper.tmpdata_bracket ctxt "" in
    begin match%lwt File.retrieve_to_unix_fd ~client capa fd' with
    | `Ok -> Lwt.return_unit | _ -> assert_failure "File.restore_to_unix_fd"
    end >>= fun () ->

    Lwt_unix.lseek fd' 0 Lwt_unix.SEEK_SET >>= fun _ ->
    let%lwt data' = Lwt_io.read (Lwt_io.of_fd ~mode:Lwt_io.input fd') in
    assert_equal ~printer:(Printf.sprintf "%s") data data';
    Lwt.return_unit
  in
  roundtrip (String.make 10 'A') >>= fun () ->
  roundtrip (String.make 200 'A')

let suite = "Test File" >::: [
    "test_create_inline" >:: run test_create_inline;
    "test_update_inline" >:: run test_update_inline;
    "test_roundtrip"     >:: run test_roundtrip;
  ]
