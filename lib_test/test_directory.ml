open OUnit2

let (>>=) = Lwt.(>>=)
let run f ctxt = Lwt_main.run (f ctxt)

let test_roundtrip ctxt =
  let _, _, _, client = Helper.blockserver_bracket ctxt in
  let tmpdir = bracket_tmpdir ~prefix:"cyldir" ctxt in
  Helper.write_file (Filename.concat tmpdir "file1") "foobar" >>= fun () ->
  Lwt_unix.mkdir (Filename.concat tmpdir "dir1") 0o755 >>= fun () ->
  (* Helper.write_file (List.fold_left Filename.concat tmpdir ["dir1"; "file2"]) "barbaz" >>= fun () -> *)
  match%lwt Directory.create_from_path ~convergence:"" ~client tmpdir with
  | `Ok dir_capa ->
    let tmpdir' = bracket_tmpdir ~prefix:"cyldir" ctxt in
    begin match%lwt Directory.retrieve_to_path ~client dir_capa tmpdir' with
    | `Ok ->
      let%lwt lst1 = Lwt_stream.to_list (Lwt_unix.files_of_directory tmpdir') in
      assert_equal ["."; ".."; "dir1"; (* "file1";  *)] (List.sort compare lst1);
      let%lwt lst2 = Lwt_stream.to_list (Lwt_unix.files_of_directory
                                            (Filename.concat tmpdir' "dir1")) in
      assert_equal ["."; ".."; (* "file2" *)] (List.sort compare lst2);
      Lwt.return_unit
    | _ -> assert_failure "Directory.retrieve_to_path"
    end
  | _ -> assert_failure "Directory.create_from_path"

let suite = "Test Directory" >::: [
    "test_roundtrip" >:: run test_roundtrip;
  ]
