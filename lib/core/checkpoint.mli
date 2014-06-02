(** Tree access control. *)

type grant  = [ `Owner | `Writer | `Reader ] * Box.public_key

type shadow = {
  updater     : Box.public_key;
  grants      : grant list;
  shadow_root : Graph.shadow Chunk.capability;
}

type shiny = {
  shiny_root  : Directory.directory Chunk.capability;
}

type keyring = {
  shadow_key  : Secret_box.key;
  shiny_key   : Secret_box.key option;
}

type checkpoint = {
  ring_key    : Box.public_key;
  keyrings    : keyring Box.box list;
  shadow      : shadow Secret_box.box;
  shiny       : shiny Secret_box.box;
}

(** [checkpoint_from_protobuf d] deserializes a checkpoint from [d]. *)
val checkpoint_from_protobuf  : Protobuf.Decoder.t -> checkpoint

(** [checkpoint_to_protobuf ca e] serializes checkpoint [ca] into [e]. *)
val checkpoint_to_protobuf    : checkpoint -> Protobuf.Encoder.t -> unit

(** [create ~convergence ~client ~owner ~server dir] creates and uploads a checkpoint for
    owner public key [owner], server public key [server] and root directory [dir]
    using convergence key [convergence] for creating the shadow tree and client [client]. *)
val create : convergence:bytes -> client:Block.Client.t ->
             owner:Box.public_key -> server:Box.public_key ->
             Directory.directory Chunk.capability ->
             [> `Ok of Block.digest | `Not_found | `Malformed
             | `Unavailable | `Not_supported ] Lwt.t

(** [unlock ~owner digest] retrieves checkpoint with from block [digest] and tries to retrieve
    the keyring corresponding to secret key [owner]. *)
val unlock : owner:Box.secret_key -> checkpoint -> keyring option
