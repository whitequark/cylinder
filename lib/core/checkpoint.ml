type grant  = [ `Owner | `Writer | `Reader ] * Box.public_key
[@@protobuf]

type shadow = {
  updater      : Box.public_key                       [@key 1];
  grants       : grant list                           [@key 2];
  shadow_root  : Graph.shadow Chunk.capability        [@key 3];
} [@@protobuf]

type capability = {
  shadow_key   : Secret_box.key                       [@key 1];
  shiny_key    : Secret_box.key                       [@key 2];
} [@@protobuf]

type checkpoint = {
  capabilities : capability Box.box list              [@key 1];
  shadow       : shadow Secret_box.box                [@key 2];
  shiny_root   : Directory.directory Chunk.capability [@key 3];
} [@@protobuf]
