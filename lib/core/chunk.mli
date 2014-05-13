(** File content storage. *)

(** A chunk is a block of file content, suitable for efficient storage.
    Invariant: [chunk.content] contains data valid for algorithm selected
    by [chunk.encoding]. *)
type chunk = private {
  encoding  : [ `None | `LZ4 ];
  content   : bytes;
}

(** [chunk_from_protobuf d] deserializes a chunk from [d]. *)
val chunk_from_protobuf : Protobuf.Decoder.t -> chunk

(** [chunk_to_protobuf ch e] serializes chunk [ch] into [e]. *)
val chunk_to_protobuf   : chunk -> Protobuf.Encoder.t -> unit

(** [chunk_of_bytes b] encodes opaque byte sequence [b] into a chunk. *)
val chunk_of_bytes      : bytes -> chunk

(** [chunk_to_bytes ch] decodes chunk [ch] into an opaque byte sequence. *)
val chunk_to_bytes      : chunk -> bytes

(** A capability is necessary and sufficient to retrieve a chunk. *)
type capability =
| Inline of bytes  (**< An [Inline] capability stores the data itself. *)
| Stored of handle (**< A [Stored] capability is a link to a Block. *)
(** The algorithm used for encrypting data to which the capability links. *)
and algorithm =
[ `SHA512_XSalsa20_Poly1305 (**< Keys are 56 bytes long. *) ]
(** All information required to retrieve and decode the data chunk.
    Invariant: [handle.key] has the lenght appropriate for [handle.algorithm]. *)
and handle = private {
  digest    : Block.digest;
  algorithm : algorithm;
  key       : bytes;
}

(** [capability_from_protobuf d] deserializes a capability from [d]. *)
val capability_from_protobuf : Protobuf.Decoder.t -> capability

(** [capability_to_protobuf ca e] serializes capability [ca] into [e]. *)
val capability_to_protobuf   : capability -> Protobuf.Encoder.t -> unit

(** [capability_of_chunk ~convergence ch] either converts chunk [ch] into
    an inline capability and returns [Inline bytes, None], or into a stored
    capability and returns [Stored handle, Some bytes], where [bytes] must
    be stored on the blockserver for the capability to be retrievable. *)
val capability_of_chunk      : convergence:bytes -> chunk -> (capability * bytes option) Lwt.t

(** [capability_of_bytes ~convergence b] ≡
    [capability_of_chunk ~convergence (chunk_of_bytes b)] *)
val capability_of_bytes      : convergence:bytes -> bytes -> (capability * bytes option) Lwt.t

(** [capability_to_chunk (ca, b)] either returns contents of an [Inline]
    capability [ca], or decrypts the contents contained in [Some bytes] [b]
    using [ca] and returns it.
    If [ca] is a [Stored] capability and [b] is [None], returns [`Malformed].
    If the encrypted data could not be authenticated, returns [`Malformed]. *)
val capability_to_chunk      : capability -> bytes option -> [ `Ok of chunk | `Malformed ] Lwt.t

(** [capability_to_bytes] is the composition of [capability_to_chunk] and [chunk_to_bytes]. *)
val capability_to_bytes      : capability -> bytes option -> [ `Ok of bytes | `Malformed ] Lwt.t

(** [retrieve_chunk cl ca] retrieves chunk directly from an [Inline]
    capability [ca], or from a [Stored] capability [ca] by sending a request
    through blockserver client [cl]. *)
val retrieve_chunk           : Block.Client.t -> capability ->
                               [ `Ok of chunk | `Not_found | `Unavailable | `Malformed ] Lwt.t

(** [store_chunk cl ca] stores a [Stored] chunk through blockserver client [cl],
    and does nothing for an [Inline] chunk.
    If [ca] is a [Stored] capability and [b] is [None], or [ca] is an [Inline] capability
    and [b] is [Some bytes], returns [`Malformed]. *)
val store_chunk              : Block.Client.t -> capability * bytes option ->
                               [ `Ok | `Unavailable | `Not_supported | `Malformed ] Lwt.t
