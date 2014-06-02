type grant = [ `Owner [@key 1] | `Writer [@key 2] | `Reader [@key 3] ] * Box.public_key
[@@protobuf]

type shadow = {
  updater     : Box.public_key                [@key 1];
  grants      : grant list                    [@key 2];
  shadow_root : Graph.shadow Chunk.capability [@key 3];
} [@@protobuf]

type shiny = {
  shiny_root  : Directory.directory Chunk.capability [@key 1];
} [@@protobuf]

type keyring = {
  shadow_key  : Secret_box.key        [@key 1];
  shiny_key   : Secret_box.key option [@key 2];
} [@@protobuf]

type checkpoint = {
  ring_key    : Box.public_key        [@key 1];
  keyrings    : keyring Box.box list  [@key 2];
  shadow      : shadow Secret_box.box [@key 3];
  shiny       : shiny Secret_box.box  [@key 4];
} [@@protobuf]

let create ~convergence ~client ~owner:owner_public ~server:server_public shiny_root =
  match%lwt Graph.directory_shadow ~convergence ~client shiny_root with
  | (`Not_found | `Malformed | `Unavailable | `Not_supported) as err -> Lwt.return err
  | `Ok shadow_root ->
    let shadow      = { updater = owner_public; grants = [`Owner, owner_public]; shadow_root }
    and shiny       = { shiny_root }
    and shadow_key  = Secret_box.random_key ()
    and shiny_key   = Secret_box.random_key () in
    let ring_secret, ring_public = Box.random_key_pair () in
    let owner_ring  = { shadow_key; shiny_key = Some shiny_key }
    and server_ring = { shadow_key; shiny_key = None } in
    let checkpoint  = {
      ring_key = ring_public;
      keyrings = [Box.store owner_ring ring_secret owner_public;
                  Box.store server_ring ring_secret server_public];
      shadow   = Secret_box.store shadow shadow_key;
      shiny    = Secret_box.store shiny shiny_key } in
    let bytes  = Protobuf.Encoder.encode_exn checkpoint_to_protobuf checkpoint in
    let digest = Block.digest_bytes bytes in
    match%lwt Block.Client.put client (fst digest) bytes with
    | (`Unavailable | `Not_supported) as err -> Lwt.return err
    | `Ok -> Lwt.return (`Ok digest)

let unlock ~owner:owner_secret checkpoint =
  try
    Some (checkpoint.keyrings |> ExtList.List.find_map (fun box ->
      Box.decrypt box owner_secret checkpoint.ring_key))
  with Not_found ->
    None

