type kind =
[ `File       [@key 1]
| `Directory  [@key 2]
| `Checkpoint [@key 3]
] [@@protobuf]

type entry = {
  name    : string       [@key 1];
  kind    : kind         [@key 2];
  content : Block.digest [@key 3];
} [@@protobuf]

type directory = entry list
[@@protobuf]

let directory_shadow directory =
  List.map (fun entry -> entry.content) directory
