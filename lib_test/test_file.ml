open OUnit2

let (>>=) = Lwt.(>>=)
let run f ctxt = Lwt_main.run (f ctxt)

let bracket_tmpdata ctxt data =
  let filename, outch = bracket_tmpfile ctxt in
  output_string outch data; flush outch; close_out outch;
  Lwt_unix.openfile filename [Lwt_unix.O_RDWR] 0

let test_create_inline ctxt =
  let _, _, _, client = Helper.blockserver_bracket ctxt in
  let%lwt fd = bracket_tmpdata ctxt "hello" in
  match%lwt File.create_from_unix_fd ~convergence:"" ~client fd with
  | `Ok { File.executable = false; chunks = [Chunk.Inline "\x7a\x05hello"] } ->
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
  let%lwt fd = bracket_tmpdata ctxt "hellobazbar" in
  begin match%lwt File.update_with_unix_fd ~convergence:"" ~client origin fd with
  | `Ok { File.chunks = [Chunk.Inline "\x7a\x05hello";
                         Chunk.Inline "\x7a\x03baz";
                         Chunk.Inline "\x7a\x03bar";] } ->
    Lwt.return_unit
  | _ -> assert_failure "File.update_with_unix_fd"
  end >>= fun () ->
  let%lwt fd = bracket_tmpdata ctxt "helloHI" in
  begin match%lwt File.update_with_unix_fd ~convergence:"" ~client origin fd with
  | `Ok { File.chunks = [Chunk.Inline "\x7a\x05hello";
                         Chunk.Inline "\x7a\x02HI";] } ->
    Lwt.return_unit
  | `Ok { File.chunks } ->
    List.iter (fun x -> print_endline (Chunk.inspect_capability x)) chunks;
    Lwt.return_unit
  | _ -> assert_failure "File.update_with_unix_fd"
  end

let test_roundtrip ctxt =
  let _, _, _, client = Helper.blockserver_bracket ctxt in
  let roundtrip data =
    let%lwt fd = bracket_tmpdata ctxt data in
    begin match%lwt File.create_from_unix_fd ~convergence:"" ~client fd with
    | `Ok file -> Lwt.return file | _ -> assert_failure "File.create_from_unix_fd"
    end >>= fun file ->

    let%lwt fd' = bracket_tmpdata ctxt "" in
    begin match%lwt File.retrieve_to_unix_fd ~client file fd' with
    | `Ok -> Lwt.return_unit | _ -> assert_failure "File.restore_to_unix_fd"
    end >>= fun () ->

    Lwt_unix.lseek fd' 0 Lwt_unix.SEEK_SET >>= fun _ ->
    let%lwt data' = Lwt_io.read (Lwt_io.of_fd ~mode:Lwt_io.input fd') in
    assert_equal ~printer:(Printf.sprintf "%s") data data';
    Lwt.return_unit
  in
  roundtrip (String.make 10 'A') >>= fun () ->
  roundtrip (String.make 200 'A')

let test_shadow ctxt =
  let%lwt capa, _ =
    Chunk.capability_of_data ~encoder:Data.data_to_protobuf ~convergence:""
                             (Data.data_of_bytes (Bytes.make 1024 'A')) in
  let file = File.{
    executable    = false;
    last_modified = Timestamp.now ();
    chunks        = [capa] } in
  assert_equal [Option.get (Chunk.capability_digest capa)] (File.file_shadow file);
  Lwt.return_unit

let suite = "Test File" >::: [
    "test_create_inline" >:: run test_create_inline;
    "test_update_inline" >:: run test_update_inline;
    "test_roundtrip"     >:: run test_roundtrip;
    "test_graph_elt"     >:: run test_shadow;
  ]
