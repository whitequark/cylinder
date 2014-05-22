let (>>=) = Lwt.(>>=)

type file = {
  last_modified : Timestamp.t                      [@key 1];
  executable    : bool                             [@key 2];
  chunks        : Data.data Chunk.capability list [@key 15];
} [@@protobuf]

exception Retry
exception Error of [ `Not_found | `Unavailable | `Malformed | `Not_supported ]

let empty = { last_modified = Timestamp.zero; executable = false; chunks = [] }

let rec update_with_unix_fd ~convergence ~client file fd =
  (* Remember mtime before we start. *)
  let%lwt { Lwt_unix.st_mtime = mtime; st_perm } = Lwt_unix.fstat fd in
  let check_mtime () =
    (* Did the file change while we were reading it? *)
    let%lwt { Lwt_unix.st_mtime = mtime' } = Lwt_unix.fstat fd in
    if mtime <> mtime' then [%lwt raise Retry] else Lwt.return_unit
  in
  try%lwt
    (* Update the chunk list while trying to share as much as possible. *)
    Lwt_unix.lseek fd 0 Lwt_unix.SEEK_SET >>= fun _ ->
    let%lwt capas =
      Lwt_list.fold_left_s (fun capas capa ->
          check_mtime () >>= fun () ->
          (* Pull out the existing chunk to compare it with present data. *)
          let%lwt old_bytes =
            match%lwt Chunk.retrieve_data ~decoder:Data.data_from_protobuf client capa with
            | `Ok data -> Lwt.return (Data.data_to_bytes data)
            | (`Not_found | `Unavailable | `Malformed) as err -> [%lwt raise (Error err)]
          in
          (* Pull out the corresponding region of the file. Mmapped access is not used,
             as truncating the file results in SIGBUS. *)
          let new_bytes = Bytes.create (Bytes.length old_bytes) in
          let%lwt length = Lwt_unix.read fd new_bytes 0 (Bytes.length new_bytes) in
          if length <> Bytes.length new_bytes then
            (* The last chunk is truncated, restart from here. *)
            Lwt_unix.lseek fd (-length) Lwt_unix.SEEK_CUR >>= fun _ ->
            Lwt.return capas
          else
            (* Compare the file with the chunk. *)
            let old_hash = Sodium.Hash.Bytes.digest old_bytes in
            let new_hash = Sodium.Hash.Bytes.digest new_bytes in
            if old_hash = new_hash then
              (* Same content. *)
              Lwt.return (capa :: capas)
            else
              (* Different content, recreate chunk. *)
              let data = Data.data_of_bytes new_bytes in
              match%lwt Chunk.store_data ~convergence ~encoder:Data.data_to_protobuf
                                         client data with
              | `Ok capa -> Lwt.return (capa :: capas)
              | (`Unavailable | `Not_supported) as err -> [%lwt raise (Error err)])
        [] file.chunks
    in
    (* Append the rest of the file to the chunk list *)
    let%lwt capas =
      let rec handle_chunk capas =
        check_mtime () >>= fun () ->
        (* Read a chunk. *)
        let bytes = Bytes.create Chunk.max_size in
        let%lwt length = Lwt_unix.read fd bytes 0 (Bytes.length bytes) in
        if length > 0 then
          (* We have a next chunk. *)
          let data = Data.data_of_bytes (Bytes.sub bytes 0 length) in
          match%lwt Chunk.store_data ~convergence ~encoder:Data.data_to_protobuf
                                     client data with
          | `Ok capa -> handle_chunk (capa :: capas)
          | (`Unavailable | `Not_supported) as err -> [%lwt raise (Error err)]
        else
          (* EOF. *)
          Lwt.return capas
      in handle_chunk capas
    in
    Lwt.return (`Ok {
      last_modified = Timestamp.of_unix_time mtime;
      executable    = st_perm land 0o100 <> 0;
      chunks        = List.rev capas; })
  with
  | Retry ->
    update_with_unix_fd ~convergence ~client file fd
  | Error ((`Malformed | `Not_found | `Not_supported | `Unavailable) as err) ->
    Lwt.return err

let create_from_unix_fd ~convergence ~client fd =
  match%lwt update_with_unix_fd ~convergence ~client empty fd with
  | `Malformed | `Not_found -> assert%lwt false
  | (`Ok _ | `Unavailable | `Not_supported) as result -> Lwt.return result

let retrieve_to_unix_fd ~client file fd =
  let ignore_espipe f =
    try%lwt f ()
    with Unix.Unix_error(Unix.ESPIPE, _, _) -> Lwt.return_unit
  in
  try%lwt
    (* Go through the chunks and write them to the file. *)
    ignore_espipe (fun () ->
      Lwt_unix.lseek fd 0 Lwt_unix.SEEK_SET >>= fun _ ->
      Lwt.return_unit) >>= fun () ->
    file.chunks |> Lwt_list.iter_s (fun capa ->
      let%lwt bytes =
        match%lwt Chunk.retrieve_data ~decoder:Data.data_from_protobuf client capa with
        | `Ok data -> Lwt.return (Data.data_to_bytes data)
        | (`Not_found | `Unavailable | `Malformed) as err -> [%lwt raise (Error err)]
      in
      Lwt_unix.write fd bytes 0 (Bytes.length bytes) >>= fun _ ->
      Lwt.return_unit) >>= fun () ->
    (* Truncate the file to its current size. *)
    ignore_espipe (fun () ->
      let%lwt length = Lwt_unix.lseek fd 0 Lwt_unix.SEEK_CUR in
      Lwt_unix.ftruncate fd length) >>= fun () ->
    (* At last, update metadata. *)
    let%lwt { Lwt_unix.st_perm } = Lwt_unix.fstat fd in
    begin if file.executable && st_perm land 0o100 = 0 then
      Lwt_unix.fchmod fd (st_perm lor 0o111)
    else if (not file.executable) && st_perm land 0o100 <> 0 then
      Lwt_unix.fchmod fd (st_perm land (lnot 0o111))
    else
      Lwt.return_unit
    end >>= fun () ->
    (* We would want to set mtimes here, but it's highly platform-specific
       and nothing in OCaml so far exports those functions. *)
    Lwt.return `Ok
  with Error ((`Malformed | `Not_found | `Unavailable) as err) ->
    Lwt.return err

