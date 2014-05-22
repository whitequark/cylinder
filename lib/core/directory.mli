(** Directory storage. *)

type entry = {
  name    : string;
  kind    : [ `File | `Directory | `Checkpoint ];
  content : Block.digest;
}

type directory = entry list

(** [directory_from_protobuf d] deserializes a directory from [d]. *)
val directory_from_protobuf : Protobuf.Decoder.t -> directory

(** [directory_to_protobuf dir e] serializes directory [dir] into [e]. *)
val directory_to_protobuf   : directory -> Protobuf.Encoder.t -> unit
