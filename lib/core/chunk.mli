(** Encrypted content-addressable storage. *)

(** [max_size] is the maximum size of the decoded chunk content, currently 10⁷ bytes. *)
val max_size            : int

(** The algorithm used for encrypting data to which the capability links. *)
type algorithm =
[ `SHA512_XSalsa20_Poly1305 (**< Keys are 56 bytes long. *) ]

(** [algorithm_to_string a] converts algorithm [a] to an ASCII string
    representation. *)
val algorithm_to_string : algorithm -> string

(** [algorithm_of_string s] converts an ASCII string to [Some algorithm]
    or returns [None] if it is unable to recognize the format. *)
val algorithm_of_string : string -> algorithm option

(** All information required to retrieve and decode the data chunk.
    Invariant: [handle.key] has the length appropriate for [handle.algorithm]. *)
type handle = private {
  digest    : Block.digest;
  algorithm : algorithm;
  key       : bytes;
}

(** A capability is necessary and sufficient to retrieve a chunk. *)
type 'a capability =
| Inline of bytes  (**< An [Inline] capability stores the data itself. *)
| Stored of handle (**< A [Stored] capability is a link to a Block. *)

(** [inspect_capability ca] converts [ca] to a human-readable string. *)
val inspect_capability        : 'a capability -> string

(** [capability_digest ca] returns [Some digest] for stored capability [ca]
    or [None] for inline capability [ca]. *)
val capability_digest         : 'a capability -> Block.digest option

(** [capability_from_protobuf d] deserializes a capability from [d]. *)
val capability_from_protobuf  : (Protobuf.Decoder.t -> 'a) ->
                                Protobuf.Decoder.t -> 'a capability

(** [capability_to_protobuf ca e] serializes capability [ca] into [e]. *)
val capability_to_protobuf    : ('a -> Protobuf.Encoder.t -> unit) ->
                                'a capability -> Protobuf.Encoder.t -> unit

(** [capability_of_string s] deserializes a capability from [s] and
    returns [Some ca] or [None] if the format is not recognized. *)
val capability_of_string      : string -> 'a capability option

(** [capability_to_string ca] serializes capability [ca] as a string.
    See {!Block.digest_to_string} for details on encoding. *)
val capability_to_string      : 'a capability -> string

(** [capability_of_data ~encoder ~convergence ch] either converts data [ch] into
    an inline capability and returns [Inline bytes, None], or into a stored
    capability and returns [Stored handle, Some bytes], where [bytes] must
    be stored on the blockserver for the capability to be retrievable. *)
val capability_of_data        : encoder:('a -> Protobuf.Encoder.t -> unit) ->
                                convergence:bytes -> 'a -> ('a capability * bytes option) Lwt.t

(** [capability_to_data ~decoder ca b] either returns contents of an [Inline]
    capability [ca], or decrypts the contents contained in [Some bytes] [b]
    using [ca] and returns it.
    If [ca] is a [Stored] capability and [b] is [None], returns [`Malformed].
    If the encrypted data could not be authenticated, returns [`Malformed]. *)
val capability_to_data        : decoder:(Protobuf.Decoder.t -> 'a) ->
                                'a capability -> bytes option ->
                                [ `Ok of 'a | `Malformed ] Lwt.t

(** [store_data ~encoder cl ca] stores data using blockserver client [cl] and
    returns a capability that would allow to access it. *)
val store_data                : encoder:('a -> Protobuf.Encoder.t -> unit) ->
                                convergence:bytes -> Block.Client.t -> 'a ->
                                [ `Ok of 'a capability | `Unavailable | `Not_supported ] Lwt.t

(** [retrieve_data ~decoder cl ca] retrieves data from capability [ca] using
    blockserver client [cl]. *)
val retrieve_data             : decoder:(Protobuf.Decoder.t -> 'a) -> Block.Client.t ->
                                'a capability ->
                                [ `Ok of 'a | `Not_found | `Unavailable | `Malformed ] Lwt.t
