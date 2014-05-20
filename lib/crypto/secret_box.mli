(** Type-safe and algorithm-agnostic secret key based encrypted container.
    The container allows serialization round-trips without decryption. *)

(** Type of keys. *)
type key

(** [key_from_protobuf d] deserializes a secret box key from [d]. *)
val key_from_protobuf : Protobuf.Decoder.t -> key

(** [key_to_protobuf k e] serializes secret box key [k] into [e]. *)
val key_to_protobuf   : key -> Protobuf.Encoder.t -> unit

(** [key_of_string d] deserializes a secret box key from string [s]. *)
val key_of_string     : string -> key option

(** [key_to_string k] serializes secret box key [k] as a string. *)
val key_to_string     : key -> string

(** [random_key ()] returns a random secret box key. *)
val random_key        : unit -> key

(** Type of serialized data in a secret box. *)
type 'a box

(** [box_from_protobuf d] deserializes a secret box from [d]. *)
val box_from_protobuf : (Protobuf.Decoder.t -> 'a) -> Protobuf.Decoder.t -> 'a box

(** [box_to_protobuf sb e] serializes secret box [sb] into [e]. *)
val box_to_protobuf   : ('a -> Protobuf.Encoder.t -> unit) -> 'a box -> Protobuf.Encoder.t -> unit

(** [store data key] stores [data] and [key] in a box. The box is not encrypted
    until it is serialized. *)
val store             : 'a -> key -> 'a box

(** [decrypt box key] decrypts the data stored in [box] using [key] and nonce
    stored together with data and returns [Some data], or [None] if verification
    failed. *)
val decrypt           : 'a box -> key -> 'a option
