(** File metadata storage. *)

type file = {
  last_modified : Timestamp.t;
  executable    : bool;
  chunks        : Data.data Chunk.capability list;
}

(** [file_from_protobuf d] deserializes file metadata from [d]. *)
val file_from_protobuf  : Protobuf.Decoder.t -> file

(** [file_to_protobuf f e] serializes file metadata [f] into [e]. *)
val file_to_protobuf    : file -> Protobuf.Encoder.t -> unit

(** [file_shadow f] returns the shadow for file [f]. *)
val file_shadow         : file -> Graph.shadow

(** [create_from_unix_fd ~convergence ~client fd] returns a file
    reflecting the metadata and content of Unix file descriptor [fd] and
    uploads the blocks representing its content via [client]. *)
val create_from_unix_fd : convergence:bytes -> client:Block.Client.t -> Lwt_unix.file_descr ->
                          [ `Ok of file | `Unavailable | `Not_supported ] Lwt.t

(** [update_with_unix_fd ~convergence ~client base fd] returns a file reflecting
    the metadata and content of Unix file descriptor [fd] and uploads the blocks
    representing its content via [client].

    The chunks which are identical in [base] and [fd] (even if [convergence] differs)
    will be shared between the input and the output file.

    [fd] will be rewound to the end of file. *)
val update_with_unix_fd : convergence:bytes -> client:Block.Client.t ->
                          file -> Lwt_unix.file_descr ->
                          [ `Ok of file | `Unavailable | `Not_supported
                          | `Not_found | `Malformed ] Lwt.t

(** [retrieve_to_unix_fd ~client file fd] updates the metadata and content of [fd],
    downloading all necessary blocks via [client].

    [fd] will be rewound to the end of file. *)
val retrieve_to_unix_fd : client:Block.Client.t -> file -> Lwt_unix.file_descr ->
                          [ `Ok | `Not_found | `Unavailable | `Malformed ] Lwt.t
