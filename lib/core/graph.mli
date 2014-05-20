(** Filesystem DAG. *)

(** A type of graph elements. *)
type 'a element = {
  content : 'a;
  updater : Box.public_key;
  edges   : Block.digest list Box.box;
}

(** [element_from_protobuf d] deserializes a graph element from [d]. *)
val element_from_protobuf   : (Protobuf.Decoder.t -> 'a) ->
                              Protobuf.Decoder.t -> 'a element

(** [element_to_protobuf ge e] serializes graph element [ge] into [e]. *)
val element_to_protobuf     : ('a -> Protobuf.Encoder.t -> unit) ->
                              'a element -> Protobuf.Encoder.t -> unit

(** [element ~server el c] creates a graph element using server public key
    [server], a list of edges [el] and content [c]. *)
val element                 : server:Box.public_key -> Block.digest list ->
                              'a -> 'a element

(** [edge_list ~server ge] retrieves the edge list from a graph element [ge]
    using the server secret key [server] and returns [Some edges], or [None]
    if verification has failed. *)
val edge_list               : server:Box.secret_key -> 'a element ->
                              Block.digest list option
