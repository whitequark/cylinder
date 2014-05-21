(** Filesystem DAG. *)

(** A type of shadow blocks. *)
type shadow = Block.digest list

(** [shadow_from_protobuf d] deserializes a shadow block from [d]. *)
val shadow_from_protobuf  : Protobuf.Decoder.t -> shadow

(** [shadow_to_protobuf sb e] serializes shadow block [sb] into [e]. *)
val shadow_to_protobuf    : shadow -> Protobuf.Encoder.t -> unit
