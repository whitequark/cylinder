(** File content storage. *)

(** A compression algorithm. *)
type encoding = [ `None | `LZ4 ]

(** [encoding_to_string e] converts encoding [e] to an ASCII string
    representation. *)
val encoding_to_string  : [ `None | `LZ4 ] -> string

(** [encoding_of_string s] converts an ASCII string to [Some encoding]
    or returns [None] if it is unable to recognize the format. *)
val encoding_of_string  : string -> [ `None | `LZ4 ] option

(** A data chunk is a block of file content, suitable for efficient storage.
    Invariant: [chunk.content] contains data valid for algorithm selected
    by [chunk.encoding]. *)
type data = private {
  encoding  : encoding;
  content   : bytes;
}

(** [data_from_protobuf d] deserializes a data chunk from [d]. *)
val data_from_protobuf : Protobuf.Decoder.t -> data

(** [data_to_protobuf ch e] serializes data chunk [ch] into [e]. *)
val data_to_protobuf   : data -> Protobuf.Encoder.t -> unit

(** [data_of_bytes b] encodes opaque byte sequence [b] into a data chunk. *)
val data_of_bytes      : bytes -> data

(** [data_to_bytes ch] decodes data chunk [ch] into an opaque byte sequence. *)
val data_to_bytes      : data -> bytes
