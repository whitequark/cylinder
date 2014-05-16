type edge_list = Block.digest list
[@@protobuf]

type 'content element = {
  content : 'content          [@key 1];
  updater : Box.public_key    [@key 2];
  edges   : edge_list Box.box [@key 3];
}
[@@protobuf]

let element ~server:server_public ~updater:(updater_secret, updater_public)
            edges content =
  { content;
    updater = updater_public;
    edges   = Box.store edges updater_secret server_public }

let edge_list ~server:server_secret { content; updater = updater_public; edges } =
  Box.decrypt edges server_secret updater_public
