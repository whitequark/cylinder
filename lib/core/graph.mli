(** Filesystem DAG. *)

(** A type of shadow blocks. *)
type shadow = {
  children : shadow Chunk.capability list;
  blocks   : Block.digest list;
}

(** [shadow_from_protobuf d] deserializes a shadow block from [d]. *)
val shadow_from_protobuf  : Protobuf.Decoder.t -> shadow

(** [shadow_to_protobuf sb e] serializes shadow block [sb] into [e]. *)
val shadow_to_protobuf    : shadow -> Protobuf.Encoder.t -> unit

(** [file_shadow f] returns the shadow for file [f]. *)
val file_shadow           : File.file -> shadow

(** [directory_shadow f] returns the shadow for directory [f]. *)
val directory_shadow      : Directory.directory -> shadow
