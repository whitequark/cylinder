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

(** [directory_of_graph_elt ~key ge] fetches directory from a graph element [ge],
    decrypts it using symmetric key [key] and returns [Some directory] if
    verification succeeds, or [None] otherwise. *)
val directory_of_graph_elt  : key:Secret_box.key -> directory Secret_box.box Graph.element ->
                              directory option

(** [directory_to_graph_elt ~server ~key dir] encrypts directory [dir] using
    symmetric key [key] and packs it into a graph element using server
    public key [server]. *)
val directory_to_graph_elt  : server:Box.public_key -> key:Secret_box.key ->
                              directory -> directory Secret_box.box Graph.element
