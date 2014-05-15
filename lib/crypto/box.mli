(** Type-safe and algorithm-agnostic public key based encrypted container.
    The container allows serialization round-trips without decryption. *)

(** Type of public keys. *)
type public_key

(** Type of secret keys. *)
type secret_key

(** Type of key pairs. *)
type key_pair = secret_key * public_key

(** [public_key_from_protobuf d] deserializes a box public key from [d]. *)
val public_key_from_protobuf : Protobuf.Decoder.t -> public_key

(** [public_key_to_protobuf pk e] serializes box public key [pk] into [e]. *)
val public_key_to_protobuf   : public_key -> Protobuf.Encoder.t -> unit

(** [secret_key_from_protobuf d] deserializes a box secret key from [d]. *)
val secret_key_from_protobuf : Protobuf.Decoder.t -> secret_key

(** [secret_key_to_protobuf pk e] serializes box secret key [pk] into [e]. *)
val secret_key_to_protobuf   : secret_key -> Protobuf.Encoder.t -> unit

(** [random_key_pair ()] returns a random box key pair. *)
val random_key_pair          : unit -> key_pair

(** Type of serialized data in a box. *)
type 'a box

(** [box_from_protobuf d] deserializes a secret box from [d]. *)
val box_from_protobuf : (Protobuf.Decoder.t -> 'a) -> Protobuf.Decoder.t -> 'a box

(** [box_to_protobuf sb e] serializes secret box [sb] into [e]. *)
val box_to_protobuf   : ('a -> Protobuf.Encoder.t -> unit) -> 'a box -> Protobuf.Encoder.t -> unit

(** [store data key] stores [data] and [key] in a box. The box is not encrypted
    until it is serialized. *)
val store             : 'a -> secret_key -> public_key -> 'a box

(** [decrypt box key] decrypts the data stored in [box] using [key] and nonce
    stored together with data and returns [Some data], or [None] if verification
    failed. *)
val decrypt           : 'a box -> secret_key -> public_key -> 'a option
