let (>>=) = Lwt.(>>=)

type content =
[ `File       [@key 1] of File.file Chunk.capability
| `Directory  [@key 2] of directory Chunk.capability
] [@@protobuf]
and entry = {
  name    : string  [@key 1];
  content : content [@key 2];
} [@@protobuf]
and directory = entry list
[@@protobuf]

exception Error of [ `Unavailable | `Not_supported | `Not_empty | `Malformed | `Not_found ]

let create_from_path ~convergence ~client path =
  let rec handle_path path =
    Lwt_unix.files_of_directory path |>
    Lwt_stream.map_list_s (fun name ->
      let full_name = Filename.concat path name in
      let%lwt stat  = Lwt_unix.stat full_name in
      match name, stat with
      | ("." | ".."), _ -> Lwt.return []
      | _, { Lwt_unix.st_kind = Lwt_unix.S_DIR } ->
        begin match%lwt handle_path full_name with
        | (`Unavailable | `Not_supported) as err -> [%lwt raise (Error err)]
        | `Ok capa -> Lwt.return [{ name; content = `Directory capa }]
        end
      | _, { Lwt_unix.st_kind = Lwt_unix.S_REG } ->
        let%lwt fd = Lwt_unix.openfile full_name [Lwt_unix.O_RDONLY] 0 in
        begin try%lwt
          match%lwt File.create_from_unix_fd ~convergence ~client fd with
          | (`Unavailable | `Not_supported) as err -> [%lwt raise (Error err)]
          | `Ok capa -> Lwt.return [{ name; content = `File capa }]
        with [%finally] ->
          Lwt_unix.close fd
        end
      | _ -> Lwt.return []) |>
    Lwt_stream.to_list >>= fun dir ->
    Chunk.store_data ~encoder:directory_to_protobuf ~convergence client dir
  in
  try%lwt
    handle_path path
  with Error ((`Not_supported | `Unavailable) as err) ->
    Lwt.return err

let retrieve_to_path ~client dir_capa path =
  let rec handle_path dir_capa path =
    (* Check that it's empty. *)
    let%lwt files = Lwt_stream.to_list (Lwt_unix.files_of_directory path) in
    let     files = List.filter (fun fn -> fn <> "." && fn <> "..") files in
    if files <> [] then raise (Error `Not_empty);
    (* Put the files in. *)
    match%lwt Chunk.retrieve_data ~decoder:directory_from_protobuf client dir_capa with
    | `Ok dir ->
      dir |> Lwt_list.iter_s (fun { name; content } ->
        let full_name = Filename.concat path name in
        match content with
        | `File file_capa ->
          let%lwt fd = Lwt_unix.openfile full_name Lwt_unix.[O_WRONLY;O_CREAT] 0o644 in
          begin try%lwt
            match%lwt File.retrieve_to_unix_fd ~client file_capa fd with
            | `Ok -> Lwt.return_unit
            | (`Not_found | `Unavailable | `Malformed) as err -> [%lwt raise (Error err)]
          with [%finally] ->
            Lwt_unix.close fd
          end
        | `Directory dir_capa ->
          Lwt_unix.mkdir full_name 0o755 >>
          handle_path dir_capa full_name)
    | (`Malformed | `Not_found | `Unavailable) as err -> [%lwt raise (Error err)]
  in
  try%lwt
    handle_path dir_capa path >> Lwt.return `Ok
  with Error ((`Not_supported | `Unavailable | `Not_empty | `Malformed | `Not_found) as err) ->
    Lwt.return err
