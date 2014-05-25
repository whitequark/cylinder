type shadow = {
  children : shadow Chunk.capability list [@key 1];
  blocks   : Block.digest list            [@key 2];
} [@@protobuf]

exception Error of [ `Not_found | `Unavailable | `Malformed | `Not_supported ]

let file_shadow ~convergence ~client file_capa =
  match%lwt Chunk.retrieve_data ~decoder:File.file_from_protobuf client file_capa with
  | (`Not_found | `Unavailable | `Malformed) as err -> Lwt.return err
  | `Ok file ->
    let blocks = ExtList.List.filter_map Chunk.capability_digest file.File.chunks in
    let blocks = match Chunk.capability_digest file_capa with
                 | Some block -> block :: blocks | None -> blocks in
    let shadow = { children = []; blocks; } in
    Chunk.store_data ~convergence ~encoder:shadow_to_protobuf client shadow

let rec directory_shadow ~convergence ~client dir_capa =
  match%lwt Chunk.retrieve_data ~decoder:Directory.directory_from_protobuf client dir_capa with
  | (`Not_found | `Unavailable | `Malformed) as err -> Lwt.return err
  | `Ok directory ->
    try%lwt
      let%lwt children =
        directory |> Lwt_list.map_s (fun entry ->
          match%lwt
            match entry.Directory.content with
            | `File capa -> file_shadow ~convergence ~client capa
            | `Directory capa -> directory_shadow ~convergence ~client capa
          with
          | (`Not_found | `Unavailable | `Malformed | `Not_supported) as err ->
            [%lwt raise (Error err)]
          | `Ok shadow -> Lwt.return shadow
          | _ -> assert false)
      in
      let shadow = { children; blocks = [] } in
      Chunk.store_data ~convergence ~encoder:shadow_to_protobuf client shadow
    with Error err ->
      Lwt.return err
