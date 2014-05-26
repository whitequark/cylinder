type grant  = [ `Owner | `Writer | `Reader ] * Box.public_key

type shadow = {
  updater      : Box.public_key;
  grants       : grant list;
  shadow_root  : Graph.shadow Chunk.capability;
}

type capability = {
  shadow_key   : Secret_box.key;
  shiny_key    : Secret_box.key;
}

type checkpoint = {
  capabilities : capability Box.box list;
  shadow       : shadow Secret_box.box;
  shiny_root   : Directory.directory Chunk.capability;
}

(** [checkpoint_from_protobuf d] deserializes a checkpoint from [d]. *)
val checkpoint_from_protobuf  : Protobuf.Decoder.t -> checkpoint

(** [checkpoint_to_protobuf ca e] serializes checkpoint [ca] into [e]. *)
val checkpoint_to_protobuf    : checkpoint -> Protobuf.Encoder.t -> unit
