(** File metadata storage. *)

type file = {
  last_modified : Timestamp.t;
  executable    : bool;
  chunks        : Chunk.capability list;
}

(** [file_from_protobuf d] deserializes file metadata from [d]. *)
val file_from_protobuf  : Protobuf.Decoder.t -> file

(** [file_to_protobuf f e] serializes file metadata [f] into [e]. *)
val file_to_protobuf    : file -> Protobuf.Encoder.t -> unit

(** [file_of_graph_elt ~key ge] fetches file from a graph element [ge],
    decrypts it using symmetric key [key] and returns [Some file] if
    verification succeeds, or [None] otherwise. *)
val file_of_graph_elt   : key:Secret_box.key -> file Secret_box.box Graph.element ->
                          file option

(** [file_to_graph_elt ~server ~updater ~key f] encrypts file [f] using
    symmetric key [key] and packs it into a graph element using server
    public key [server] and client keypair [updater]. *)
val file_to_graph_elt   : server:Box.public_key -> updater:Box.key_pair ->
                          key:Secret_box.key -> file -> file Secret_box.box Graph.element

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
