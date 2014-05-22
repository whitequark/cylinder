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

(** [create_from_unix_fd ~convergence ~client fd] returns a file capability
    reflecting the metadata and content of Unix file descriptor [fd] and
    uploads the blocks representing its content via [client].

    [fd] will be rewound to the end of file. *)
val create_from_unix_fd : convergence:bytes -> client:Block.Client.t -> Lwt_unix.file_descr ->
                          [ `Ok of file Chunk.capability | `Unavailable | `Not_supported ] Lwt.t

(** [update_with_unix_fd ~convergence ~client base fd] returns a file capability
    reflecting the metadata and content of Unix file descriptor [fd], uploading
    the chunks via [client].

    The data chunks which are identical in [base] and [fd] (even if [convergence] differs)
    will be shared between the input and the output file.

    [fd] will be rewound to the end of file. *)
val update_with_unix_fd : convergence:bytes -> client:Block.Client.t ->
                          file Chunk.capability -> Lwt_unix.file_descr ->
                          [ `Ok of file Chunk.capability | `Unavailable | `Not_supported
                          | `Not_found | `Malformed ] Lwt.t

(** [retrieve_to_unix_fd ~client file fd] updates the metadata and content of [fd],
    downloading chunks via [client].

    [fd] will be rewound to the end of file. *)
val retrieve_to_unix_fd : client:Block.Client.t -> file Chunk.capability -> Lwt_unix.file_descr ->
                          [ `Ok | `Not_found | `Unavailable | `Malformed ] Lwt.t
