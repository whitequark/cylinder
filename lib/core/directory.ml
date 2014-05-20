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

let directory_of_graph_elt ~key graph_elt =
  Secret_box.decrypt graph_elt.Graph.content key

let directory_to_graph_elt ~server ~key dir =
  let edges      = List.map (fun entry -> entry.content) dir in
  let secret_box = Secret_box.store dir key in
  Graph.element ~server edges secret_box
