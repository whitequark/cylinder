type shadow = {
  children : shadow Chunk.capability list [@key 1];
  blocks   : Block.digest list            [@key 2];
} [@@protobuf]

let file_shadow ~convergence ~client file_capa =
  match%lwt Chunk.retrieve_data ~decoder:File.file_from_protobuf client file_capa with
  | (`Not_found | `Unavailable | `Malformed) as err -> Lwt.return err
  | `Ok file ->
    let blocks = ExtList.List.filter_map Chunk.capability_digest file.File.chunks in
    let blocks = match Chunk.capability_digest file_capa with
                 | Some block -> block :: blocks | None -> blocks in
    let shadow = { children = []; blocks; } in
    Chunk.store_data ~convergence ~encoder:shadow_to_protobuf client shadow

let directory_shadow ~convergence ~client dir_capa =
  assert false(*
  { children = [];
    blocks   = List.map (fun entry -> entry.Directory.content) directory } *)
