(** Directory storage. *)

type content =
[ `File       [@key 1] of File.file Chunk.capability
| `Directory  [@key 2] of directory Chunk.capability
]
and entry = {
  name    : string  [@key 1];
  content : content [@key 2];
}
and directory = entry list

(** [directory_from_protobuf d] deserializes a directory from [d]. *)
val directory_from_protobuf : Protobuf.Decoder.t -> directory

(** [directory_to_protobuf dir e] serializes directory [dir] into [e]. *)
val directory_to_protobuf   : directory -> Protobuf.Encoder.t -> unit

(** [create_from_path ~convergence ~client fd] returns a directory capability
    reflecting the metadata and content of a directory at [path] and
    uploads the blocks representing its content via [client].
    @see {!File.create_with_path} *)
val create_from_path : convergence:bytes -> client:Block.Client.t -> string ->
                       [ `Ok of directory Chunk.capability | `Unavailable | `Not_supported ] Lwt.t

(** [retrieve_to_path ~client dir_capa fd] fills an empty directory [dir] using
    the metadata and content of a directory with capability [dir_capa],
    downloading chunks via [client].
    @see {!File.retrieve_to_path} *)
val retrieve_to_path : client:Block.Client.t -> directory Chunk.capability -> string ->
                       [ `Ok | `Not_empty | `Not_found | `Not_supported
                       | `Unavailable | `Malformed ] Lwt.t
