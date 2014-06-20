let (>>=) = Lwt.(>>=)

type t = Pathname.t

let create path =
  FileUtil.mkdir ~parent:true path;
  Pathname.of_string path

let pathname_of_digest root digest =
  let str = Block.digest_to_string digest in
  let p1, p2, p3, r = String.sub str 0 5, String.sub str 5 2,
                      String.sub str 7 2, String.sub str 9 (String.length str - 9) in
  Pathname.concat root (Pathname.of_list [p1;p2;p3;r])

let get root digest =
  let path = pathname_of_digest root digest in
  try%lwt
    let%lwt file    = Lwt_io.open_file ~mode:Lwt_io.input (Pathname.to_string path) in
    let%lwt content = Lwt_io.read file in
    Lwt_io.close file >>
    Lwt.return (`Ok content)
  with Unix.Unix_error _ ->
    Lwt.return `Not_found

let exists root digest =
  let path = pathname_of_digest root digest in
  try%lwt Lwt_unix.stat (Pathname.to_string path) >>= fun _ -> Lwt.return `Ok
  with    Unix.Unix_error _ -> Lwt.return `Not_found

let put root digest obj =
  let path = pathname_of_digest root digest in
  try%lwt
    FileUtil.mkdir ~parent:true (Pathname.to_string (Pathname.basename path));
    let%lwt file = Lwt_io.open_file ~mode:Lwt_io.output (Pathname.to_string path) in
    Lwt_io.write file obj >>
    Lwt_io.close file >>
    Lwt.return `Ok
  with Unix.Unix_error _ ->
    Lwt.return `Unavailable

let erase root digest =
  let path = pathname_of_digest root digest in
  Lwt_unix.unlink (Pathname.to_string path) >>
  Lwt.return_unit

let rec file_list root path cookie fuel =
  Lwt_stream.fold_s (fun filename (cookie, digests, fuel) ->
      if String.compare filename cookie > 0 && fuel > 0 then
        let path = Pathname.extend path filename in
        try%lwt
          let%lwt stat = Lwt_unix.stat (Pathname.to_string (Pathname.concat root path)) in
          match stat.Lwt_unix.st_kind with
          | Lwt_unix.S_REG ->
            let digest = Pathname.to_list path |> String.concat "" in
            Lwt.return (digest, (Option.get (Block.digest_of_string digest)) :: digests, fuel - 1)
          | Lwt_unix.S_DIR ->
            file_list root path cookie fuel
          | _ ->
            Lwt.return (cookie, digests, fuel)
        with Unix.Unix_error _ ->
          Lwt.return (cookie, digests, fuel)
      else
        Lwt.return (cookie, digests, fuel))
    (Lwt_unix.files_of_directory (Pathname.to_string root))
    ("", [], fuel)

let enumerate root cookie =
  match%lwt file_list root Pathname.empty cookie 1000 with
  | _, [], _ -> Lwt.return `Exhausted
  | cookie, digests, 0 -> Lwt.return (`Ok (cookie, digests))
  | _ -> assert false
