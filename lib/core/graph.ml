type shadow = {
  children : shadow Chunk.capability list [@key 1];
  blocks   : Block.digest list            [@key 2];
} [@@protobuf]

let file_shadow file =
  { children = [];
    blocks   = ExtList.List.filter_map Chunk.capability_digest file.File.chunks }

let directory_shadow directory =
  { children = [];
    blocks   = List.map (fun entry -> entry.Directory.content) directory }
