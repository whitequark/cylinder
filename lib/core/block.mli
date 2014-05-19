(** An opaque block storage client and server. *)

(** A [digest_kind] indicates the function used for creating the digest. *)
type digest_kind = [ `SHA512 ]

(** [digest_kind_to_string dk] converts digest kind [dk] to an ASCII string
    representation. *)
val digest_kind_to_string : digest_kind -> string

(** [digest_kind_of_string s] converts an ASCII string to [Some digest_kind]
    or returns [None] if it is unable to recognize the format. *)
val digest_kind_of_string : string -> digest_kind option

(** A [digest] is required and sufficient to retrieve a chunk of opaque data. *)
type digest = digest_kind * bytes

(** [inspect_digest d] converts [d] to a human-readable string. *)
val inspect_digest        : digest -> string

(** [digest_bytes b] hashes [b] with the preferred function, or returns an [`Inline]
    digest if [b] is shorter than the length of hash function output. *)
val digest_bytes          : bytes -> digest

(** [verify_bytes d b] checks whether digest [d] is indeed the digest of [b]. *)
val verify_bytes          : digest -> bytes -> bool

(** [digest_bigbytes b] behaves like [digest_bytes]. *)
val digest_bigbytes       : Lwt_bytes.t -> digest

(** [digest_from_protobuf d] deserializes a digest from [d]. *)
val digest_from_protobuf  : Protobuf.Decoder.t -> digest

(** [digest_to_protobuf d e] serializes digest [d] into [e]. *)
val digest_to_protobuf    : digest -> Protobuf.Encoder.t -> unit

(** [digest_to_string d] converts digest [d] to an ASCII string representation,
    encoded . *)
val digest_to_string      : digest -> string

(** [digest_of_string s] converts an ASCII string to [Some digest] or returns [None]
    if it is unable to recognize the format. *)
val digest_of_string      : string -> digest option

(** [BACKEND] is the type of modules implementing blockserver backends. *)
module type BACKEND = sig
  (** The type of backends. *)
  type t

  (** [get bd digest] retrieves an object corresponding to [digest] from [bd]
      and returns [`Ok object].
      If the object does not exist, [`Not_found] is returned.
      If the backend is temporarily unavailable, e.g. due to a severed network link,
      [`Unavailable] is returned. *)
  val get       : t -> digest -> [> `Ok of string | `Not_found | `Unavailable ] Lwt.t

  (** [put bd digest obj] places an object [obj] to [bd] corresponding to digest
      [digest] and returns [`Ok]. No verification of [digest] is performed.
      If the backend is temporarily unavailable, e.g. due to a severed network link
      or lack of disk space, [`Unavailable] is returned. *)
  val put       : t -> digest -> string -> [> `Ok | `Unavailable ] Lwt.t

  (** [erase bd digest] attempts to remove an object corresponding to [digest] from
      [bd]. If there is no corresponding object or the backend is unavailable,
      does nothing. *)
  val erase     : t -> digest -> unit Lwt.t

  (** [enumerate bd] traverses all digests in [bd]. The stream may include digests not
      in [bd], or, conversely, may not include digests in [bd] at the time, because more
      digests may have been added or erased while the request was in flight.

      To spread the workload through several requests, [enumerate] accepts a cookie,
      which is an opaque string, and returns a cookie that must be passed back at
      the next request. The cookie contains all state required to perform traversing. *)
  val enumerate : t -> string -> [ `Ok of (string * digest list) | `Exhausted ] Lwt.t
end

module Server(Backend: BACKEND) : sig
  (** The type of storage servers. *)
  type t

  (** [create backend sock] creates a server for backend [backend] and a ZeroMQ
      socket [sock].
      The maximum message length of [sock] is set to [16_777_211]. *)
  val create    : Backend.t -> [`Router] ZMQ.Socket.t -> t

  (** [to_socket server] returns the ZeroMQ socket used by [server]. *)
  val to_socket : t -> [`Router] ZMQ.Socket.t

  (** [listen server] starts and returns a thread that handles requests to [server].
      The thread will terminate on any unexpected failure. *)
  val listen    : t -> unit Lwt.t
end

module Client : sig
  (** The type of storage clients. *)
  type t

  (** [create sock] creates a client for a ZeroMQ socket [sock].
      The maximum message length of [sock] is set to [16_777_211]. *)
  val create    : [`Req] ZMQ.Socket.t -> t

  (** [to_socket client] returns the ZeroMQ socket used by [client]. *)
  val to_socket : t -> [`Req] ZMQ.Socket.t

  (** See {!BACKEND.get}. If the returned data doesn't match the digest, returns [`Malformed] *)
  val get       : t -> digest -> [ `Ok of string | `Not_found | `Unavailable | `Malformed ] Lwt.t

  (** See {!BACKEND.put}. *)
  val put       : t -> digest_kind -> string -> [ `Ok | `Unavailable | `Not_supported ] Lwt.t

  (** See {!BACKEND.erase}. If this client is not authorized to perform erase operations,
      returns [`Forbidden]. *)
  val erase     : t -> digest -> [ `Ok | `Forbidden ] Lwt.t

  (** See {!BACKEND.enumerate}. If this client is not authorized to perform enumerate
      operations, returns [`Forbidden]. *)
  val enumerate : t -> string -> [ `Ok of (string * digest list) | `Exhausted | `Forbidden ] Lwt.t

  (** [digests client] returns a stream of all digests, collected through [enumerate].
      If this client is not authorized to perform enumerate  operations, returns [`Forbidden]. *)
  val digests   : t -> [> `Ok of digest Lwt_stream.t | `Forbidden ] Lwt.t
end
