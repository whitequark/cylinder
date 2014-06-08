let (>>=) = Lwt.(>>=)

let (>:=) x f =
  match%lwt x with
  | (`Error _) as err -> Lwt.return err
  | `Ok value -> f value

let return_ok = Lwt.return (`Ok ())
let return_val v = Lwt.return (`Ok v)
let return_error v = Lwt.return (`Error (false, v))
let return_error_f fmt = Printf.kprintf return_error fmt

(* Command implementation *)

type backend_kind = In_memory_backend

let zmq_key key =
  match key with
  | { Box.algorithm = `Curve25519_XSalsa20_Poly1305; key } -> key

let resolve host service =
  let open Lwt_unix in
  let rec find_addr ais =
    match ais with
    | {ai_family = PF_INET; ai_addr = ADDR_INET(addr, port)}::_ ->
      return_val (Unix.string_of_inet_addr addr, port)
    | {ai_family = PF_INET6; ai_addr = ADDR_INET(addr, port)}::_ ->
      return_val ("[" ^ (Unix.string_of_inet_addr addr) ^ "]", port)
    | _ :: rest -> find_addr rest
    | [] -> return_error_f "cannot resolve %s:%s" host service
  in
  getprotobyname "tcp" >>= fun pe ->
  getaddrinfo host service [AI_PROTOCOL pe.p_proto] >>=
  find_addr

let init_server_config () =
  let open Server_config in
  Config.init ~app:"cylinder" ~name:"server.json"
              ~loader:server_config_of_string
              ~dumper:server_config_to_string
              ~init:(fun () ->
    Lwt_log.ign_notice "Generating a new server key pair";
    let secret_key, public_key = Box.random_key_pair () in
    { secret_key; public_key })

let in_memory_listener socket =
  let module Server = Block.Server(In_memory_store) in
  let backend = In_memory_store.create () in
  Server.listen (Server.create backend socket)

let server listener host port =
  let open Server_config in
  let config = init_server_config () in
  let zcontext = ZMQ.Context.create () in
  let zsocket  = ZMQ.Socket.create zcontext ZMQ.Socket.router in
  ZMQ.Socket.set_ipv6 zsocket true;
  ZMQ.Socket.set_max_message_size zsocket Block.max_message_size;
  begin try
    let secret_key = zmq_key (config.secret_key : Box.secret_key :> Box.key) in
    ZMQ.Socket.set_curve_server    zsocket true;
    ZMQ.Socket.set_curve_secretkey zsocket secret_key
  with Unix.Unix_error(Unix.EINVAL, "zmq_setsockopt", _) ->
    failwith "libzmq was compiled without libsodium"
  end;
  Lwt_log.notice_f "Public key: %s" (Box.public_key_to_string config.public_key) >>= fun () ->
  resolve host (string_of_int port) >:= fun (addr, port) ->
  try
    ZMQ.Socket.bind zsocket (Printf.sprintf "tcp://%s:%d" addr port);
    Lwt_log.notice_f "Listening at %s:%d..." addr port >>= fun () ->
    listener zsocket >>= fun () ->
    return_ok
  with exn ->
    return_error_f "Cannot bind to %s:%d" addr port

let load_client_config () =
  match Config.load ~app:"cylinder" ~name:"client.json"
                    ~loader:Client_config.client_config_of_string with
  | None -> return_error "No client configuration found. Use the client-init command."
  | Some config -> return_val config

let init_client host port server_key =
  let open Client_config in
  let secret_key, public_key =
    match Config.load ~app:"cylinder" ~name:"client.json"
                      ~loader:Client_config.client_config_of_string with
    | Some config -> config.secret_key, config.public_key
    | None ->
      Lwt_log.ign_notice "Generating a new client key pair";
      Box.random_key_pair ()
  in
  Config.store ~app:"cylinder" ~name:"client.json"
               ~dumper:Client_config.client_config_to_string {
    secret_key; public_key; server_key;
    server_host = host;
    server_port = port;
  }

let connect () =
  let open Client_config in
  load_client_config () >:= fun config ->
  let zcontext = ZMQ.Context.create () in
  let zsocket  = ZMQ.Socket.create zcontext ZMQ.Socket.req in
  ZMQ.Socket.set_ipv6 zsocket true;
  ZMQ.Socket.set_max_message_size zsocket Block.max_message_size;
  let secret_key = zmq_key (config.secret_key : Box.secret_key :> Box.key)
  and public_key = zmq_key (config.public_key : Box.public_key :> Box.key)
  and server_key = zmq_key (config.server_key : Box.public_key :> Box.key) in
  ZMQ.Socket.set_curve_server zsocket false;
  ZMQ.Socket.set_curve_secretkey zsocket secret_key;
  ZMQ.Socket.set_curve_publickey zsocket public_key;
  ZMQ.Socket.set_curve_serverkey zsocket server_key;
  resolve config.server_host (string_of_int config.server_port) >:= fun (addr, port) ->
  ZMQ.Socket.connect zsocket (Printf.sprintf "tcp://%s:%d" addr port);
  return_val (config, Block.Client.create zsocket)

let handle_error err =
  match err with
  | `Unavailable ->
    return_error "Blockserver is unavailable"
  | `Not_supported ->
    return_error "Blockserver does not support this digest kind"
  | `Not_found ->
    return_error "A requested block is missing"
  | `Malformed ->
    return_error "Stored data is corrupted"
  | `Not_empty ->
    return_error "Directory is not empty"

let istream_of_filename filename =
  if filename = "-"
  then Lwt.return Lwt_io.stdin
  else Lwt_io.open_file ~mode:Lwt_io.input filename

let ostream_of_filename filename =
  if filename = "-"
  then Lwt.return Lwt_io.stdout
  else Lwt_io.open_file ~mode:Lwt_io.output filename

let get_block force digest =
  connect () >:= fun (config, client) ->
  if not (Unix.isatty Unix.stdout) || force then
    match%lwt Block.Client.get client digest with
    | (`Not_found | `Unavailable | `Malformed) as err -> handle_error err
    | `Ok bytes -> print_bytes bytes; return_ok
  else
    return_error "You are attempting to output binary data to a terminal. \
                  This is inadvisable, as it may cause display problems. \
                  Pass -f/--force if you really want to taste it firsthand."

let put_block digest_kind filename =
  connect () >:= fun (config, client) ->
  let%lwt data = istream_of_filename filename >>= Lwt_io.read in
  match%lwt Block.Client.put client digest_kind data with
  | (`Unavailable | `Not_supported) as err -> handle_error err
  | `Ok ->
    Lwt_io.printl (Block.digest_to_string (Block.digest_bytes data)) >>= fun () ->
    return_ok

let show_chunk capa =
  connect () >:= fun (config, client) ->
  match capa with
  | Chunk.Inline bytes ->
    Lwt_io.printl  "Type:      inline" >>= fun () ->
    Lwt_io.printlf "Length:    %d bytes" (Bytes.length bytes) >>= fun () ->
    return_ok
  | Chunk.Stored { Chunk.digest; algorithm; key } ->
    Lwt_io.printl  "Type:      stored" >>= fun () ->
    Lwt_io.printlf "Algorithm: %s" (Chunk.algorithm_to_string algorithm) >>= fun () ->
    Lwt_io.printlf "Key:       %s" (Base64_url.encode key) >>= fun () ->
    Lwt_io.printlf "Digest:    %s" (Block.digest_to_string digest) >>= fun () ->
    return_ok

let get_chunk ~decoder client capa =
  match%lwt Chunk.retrieve_data ~decoder client capa with
  | (`Not_found | `Unavailable | `Malformed ) as err -> handle_error err
  | (`Ok _) as result -> Lwt.return result

let put_chunk ~convergence ~encoder client data =
  match%lwt Chunk.store_data ~convergence ~encoder client data with
  | (`Unavailable | `Not_supported ) as err -> handle_error err
  | (`Ok _) as result -> Lwt.return result

let show_data capa =
  connect () >:= fun (config, client) ->
  get_chunk ~decoder:Data.data_from_protobuf client capa >:= fun { Data.encoding; content } ->
  Lwt_io.printlf "Encoding: %s" (Data.encoding_to_string encoding) >>= fun () ->
  Lwt_io.printlf "Length:   %d bytes" (Bytes.length content) >>= fun () ->
  return_ok

let store_data convergence filename =
  connect () >:= fun (config, client) ->
  let%lwt input = istream_of_filename filename >>= Lwt_io.read in
  put_chunk ~convergence ~encoder:Data.data_to_protobuf
            client (Data.data_of_bytes input) >:= fun capa ->
  Lwt_io.printl (Chunk.capability_to_string capa) >>= fun () ->
  return_ok

let retrieve_data capa filename =
  connect () >:= fun (config, client) ->
  get_chunk ~decoder:Data.data_from_protobuf client capa >:= fun data ->
  let%lwt stream = ostream_of_filename filename in
  Lwt_io.write stream (Data.data_to_bytes data) >>= fun () ->
  return_ok

let show_shadow capa =
  connect () >:= fun (config, client) ->
  get_chunk ~decoder:Graph.shadow_from_protobuf client capa >:= fun shadow ->
  let { Graph.children; blocks } = shadow in
  Lwt_io.printl "Children:" >>= fun () ->
  Lwt_list.iter_s Lwt_io.printl (List.map Chunk.capability_to_string children) >>= fun () ->
  Lwt_io.printl "Blocks:" >>= fun () ->
  Lwt_list.iter_s Lwt_io.printl (List.map Block.digest_to_string blocks) >>= fun () ->
  return_ok

let unix_fd_of_filename filename mode =
  if filename = "-"
  then Lwt.return Lwt_unix.stdout
  else Lwt_unix.openfile filename mode 0o644

let show_file capa =
  connect () >:= fun (config, client) ->
  get_chunk ~decoder:File.file_from_protobuf client capa >:= fun file ->
  Lwt_io.printlf "Modified:   %s" (Timestamp.to_string file.File.last_modified) >>= fun () ->
  Lwt_io.printlf "Executable: %B" file.File.executable >>= fun () ->
  Lwt_io.printl  "Chunks:" >>= fun () ->
  file.File.chunks |> Lwt_list.iter_s (fun capa ->
    Lwt_io.printl (Chunk.capability_to_string capa)) >>= fun () ->
  return_ok

let store_file convergence data =
  connect () >:= fun (config, client) ->
  let%lwt fd = unix_fd_of_filename data Lwt_unix.[O_RDONLY] in
  match%lwt File.create_from_unix_fd ~convergence ~client fd with
  | (`Unavailable | `Not_supported) as err -> handle_error err
  | `Ok file_capa ->
    Lwt_io.printl (Chunk.capability_to_string file_capa) >>= fun () ->
    return_ok

let retrieve_file capa data =
  connect () >:= fun (config, client) ->
  let%lwt fd = unix_fd_of_filename data Lwt_unix.[O_WRONLY; O_CREAT] in
  match%lwt File.retrieve_to_unix_fd ~client capa fd with
  | (`Not_found | `Unavailable | `Malformed) as err -> handle_error err
  | `Ok -> return_ok

let store_directory convergence path =
  connect () >:= fun (config, client) ->
  match%lwt Directory.create_from_path ~convergence ~client path with
  | (`Unavailable | `Not_supported) as err -> handle_error err
  | `Ok dir_capa ->
    Lwt_io.printl (Chunk.capability_to_string dir_capa) >>= fun () ->
    return_ok

let retrieve_directory capa path =
  connect () >:= fun (config, client) ->
  match%lwt Directory.retrieve_to_path ~client capa path with
  | (`Not_found | `Unavailable | `Malformed |
     `Not_supported | `Not_empty) as err -> handle_error err
  | `Ok -> return_ok

let shadow fn convergence capa =
  connect () >:= fun (config, client) ->
  match%lwt fn ~convergence ~client capa with
  | (`Not_found | `Unavailable | `Malformed | `Not_supported) as err -> handle_error err
  | `Ok shadow_capa ->
    Lwt_io.printl (Chunk.capability_to_string shadow_capa) >>= fun () ->
    return_ok

let shadow_file = shadow Graph.file_shadow
let shadow_directory = shadow Graph.directory_shadow

let create_checkpoint convergence dir_capa =
  let open Client_config in
  connect () >:= fun (config, client) ->
  match%lwt Checkpoint.create ~convergence ~client
                              ~owner:config.public_key ~server:config.server_key dir_capa with
  | (`Not_found | `Unavailable | `Malformed | `Not_supported) as err -> handle_error err
  | `Ok digest ->
    Lwt_io.printl (Block.digest_to_string digest) >>= fun () ->
    return_ok

let show_checkpoint digest =
  let open Client_config in
  connect () >:= fun (config, client) ->
  match%lwt Block.Client.get client digest with
  | (`Not_found | `Unavailable | `Malformed) as err -> handle_error err
  | `Ok bytes ->
    let checkpoint = Protobuf.Decoder.decode_exn Checkpoint.checkpoint_from_protobuf bytes in
    Lwt_io.printlf "Ring key:    %s" (Box.public_key_to_string checkpoint.Checkpoint.ring_key) >>= fun () ->
    match Checkpoint.unlock ~owner:config.secret_key checkpoint with
    | None ->
      Lwt_io.printl "No access." >>= fun () ->
      return_ok
    | Some keyring ->
      match Secret_box.decrypt checkpoint.Checkpoint.shadow keyring.Checkpoint.shadow_key with
      | None -> return_error "Cannot decrypt shadow."
      | Some shadow ->
        Lwt_io.printlf "Updater:     %s" (Box.public_key_to_string shadow.Checkpoint.updater) >>= fun () ->
        Lwt_io.printl  "Grants:" >>= fun () ->
        shadow.Checkpoint.grants |> Lwt_list.iter_s (fun (level, public_key) ->
          let level' = match level with `Owner -> "Owner " | `Writer -> "Writer" | `Reader -> "Reader" in
          Lwt_io.printlf "%s %s" (Box.public_key_to_string shadow.Checkpoint.updater) level') >>= fun () ->
        let shadow_root = Chunk.capability_to_string shadow.Checkpoint.shadow_root in
        Lwt_io.printlf "Shadow root: %s" shadow_root >>= fun () ->
        match keyring.Checkpoint.shiny_key with
        | Some shiny_key ->
          begin match Secret_box.decrypt checkpoint.Checkpoint.shiny shiny_key with
          | None -> return_error "Cannot decrypt shiny."
          | Some shiny ->
            let shiny_root = Chunk.capability_to_string shiny.Checkpoint.shiny_root in
            Lwt_io.printlf "Shiny root:  %s" shiny_root >>= fun () ->
            return_ok
          end
        | None ->
          Lwt_io.printl  "No shiny access." >>= fun () ->
          return_ok

(* Command specification *)

open Cmdliner

let make_arg_conv of_string to_string error =
  (fun str ->
    match of_string str with
    | Some x -> `Ok x | None -> `Error error),
  (fun fmt digest ->
    Format.pp_print_string fmt (to_string digest))

let digest_kind =
  make_arg_conv Block.digest_kind_of_string Block.digest_kind_to_string
                "Invalid digest kind format"

let digest =
  make_arg_conv Block.digest_of_string Block.digest_to_string
                "Invalid digest format"

let capability =
  (fun str ->
    match Chunk.capability_of_string str with
    | Some x -> `Ok x | None -> `Error "Invalid capability format"),
  (fun fmt digest ->
    Format.pp_print_string fmt (Chunk.capability_to_string digest))

let base64url =
  make_arg_conv Base64_url.decode Base64_url.encode
                "Invalid base64url encoding"

let public_key =
  make_arg_conv Box.public_key_of_string Box.public_key_to_string
                "Invalid public key format"

let symmetric_key =
  make_arg_conv Secret_box.key_of_string Secret_box.key_to_string
                "Invalid symmetric key format"

let docs = "HIGH-LEVEL COMMANDS"

let server_cmd doc listener =
  let address =
    let doc = "Bind ZeroMQ socket to address $(docv)" in
    Arg.(value & opt string "::" & info ["b"; "bind-to"] ~docv:"ADDRESS" ~doc)
  in
  let port =
    let doc = "Bind ZeroMQ socket to port $(docv)" in
    Arg.(value & opt int 5555 & info ["p"; "port"] ~docv:"PORT" ~doc)
  in
  Term.(ret (pure Lwt_main.run $ (pure server $ listener $ address $ port))),
  Term.info "server" ~doc ~docs

let in_memory_server_cmd =
  let doc = "run a server with in-memory storage" in
  server_cmd doc Term.(pure in_memory_listener)

let init_client_cmd =
  let address =
    let doc = "Connect to address $(docv)" in
    Arg.(value & opt string "localhost" & info ["a"; "address"] ~docv:"ADDRESS" ~doc)
  in
  let port =
    let doc = "Connect to port $(docv)" in
    Arg.(value & opt int 5555 & info ["p"; "port"] ~docv:"PORT" ~doc)
  in
  let server_key =
    let doc = "Use server public key $(docv)" in
    Arg.(required & opt (some public_key) None & info ["k"; "server-key"] ~docv:"KEY" ~doc)
  in
  let doc = "configure client" in
  Term.(pure init_client $ address $ port $ server_key),
  Term.info "init-client" ~doc ~docs

let docs = "LOW-LEVEL COMMANDS"

let force =
  let doc = "Output raw data to terminal" in
  Arg.(value & flag & info ["f"; "force"] ~doc)

let digest p =
  let doc = "Retrieve block with digest $(docv)" in
  Arg.(required & pos p (some digest) None & info [] ~docv:"DIGEST" ~doc)

let get_block_cmd =
  let doc = "retrieve a block" in
  Term.(ret (pure Lwt_main.run $ (pure get_block $ force $ (digest 0)))),
  Term.info "get-block" ~doc ~docs

let data_in p =
  let doc = "Read data from file $(docv), or stdin if $(docv) is \"-\"" in
  Arg.(value & pos p string "-" & info [] ~docv:"DATA" ~doc)

let data_out p =
  let doc = "Write data to file $(docv), or stdout if $(docv) is \"-\"" in
  Arg.(value & pos p string "-" & info [] ~docv:"DATA" ~doc)

let put_block_cmd =
  let digest_kind =
    let doc = "Store block with digest kind $(docv) (one of: sha512)" in
    Arg.(value & opt digest_kind `SHA512 & info ["k"; "kind"] ~docv:"KIND" ~doc)
  in
  let doc = "store a block" in
  Term.(ret (pure Lwt_main.run $ (pure put_block $ digest_kind $ data_in 0))),
  Term.info "put-block" ~doc ~docs

let capability p =
  let doc = "Retrieve chunk with capability $(docv)" in
  Arg.(required & pos p (some capability) None & info [] ~docv:"CAPABILITY" ~doc)

let show_chunk_cmd =
  let doc = "show chunk properties" in
  Term.(ret (pure Lwt_main.run $ (pure show_chunk $ capability 0))),
  Term.info "show-chunk" ~doc ~docs

let convergence =
  let doc = "Use specified convergence key (in RFC 4648 'base64url' format)" in
  Arg.(value & opt base64url "" & info ["c"; "convergence-key"] ~docv:"KEY" ~doc)

let show_data_cmd =
  let doc = "show data properties" in
  Term.(ret (pure Lwt_main.run $ (pure show_data $ capability 0))),
  Term.info "show-data" ~doc ~docs

let store_data_cmd =
  let doc = "store data" in
  Term.(ret (pure Lwt_main.run $ (pure store_data $ convergence $ data_in 0))),
  Term.info "store-data" ~doc ~docs

let retrieve_data_cmd =
  let doc = "retrieve data" in
  Term.(ret (pure Lwt_main.run $ (pure retrieve_data $ capability 0 $ data_out 1))),
  Term.info "retrieve-data" ~doc ~docs

let show_shadow_cmd =
  let doc = "show shadow properties" in
  Term.(ret (pure Lwt_main.run $ (pure show_shadow $ capability 0))),
  Term.info "show-shadow" ~doc ~docs

let show_file_cmd =
  let doc = "show file" in
  Term.(ret (pure Lwt_main.run $ (pure show_file $ capability 0))),
  Term.info "show-file" ~doc ~docs

let store_file_cmd =
  let doc = "store file" in
  Term.(ret (pure Lwt_main.run $ (pure store_file $ convergence $ data_in 0))),
  Term.info "store-file" ~doc ~docs

let retrieve_file_cmd =
  let doc = "retrieve file" in
  Term.(ret (pure Lwt_main.run $ (pure retrieve_file $ capability 0 $ data_out 1))),
  Term.info "retrieve-file" ~doc ~docs

let directory p =
  let doc = "Use directory $(docv)" in
  Arg.(required & pos p (some string) None & info [] ~docv:"DIRECTORY" ~doc)

let store_directory_cmd =
  let doc = "store directory" in
  Term.(ret (pure Lwt_main.run $ (pure store_directory $ convergence $ directory 0))),
  Term.info "store-directory" ~doc ~docs

let retrieve_directory_cmd =
  let doc = "retrieve directory" in
  Term.(ret (pure Lwt_main.run $ (pure retrieve_directory $ capability 0 $ directory 1))),
  Term.info "retrieve-directory" ~doc ~docs

let shadow_file_cmd =
  let doc = "create a file shadow" in
  Term.(ret (pure Lwt_main.run $ (pure shadow_file $ convergence $ capability 0))),
  Term.info "shadow-file" ~doc ~docs

let shadow_directory_cmd =
  let doc = "create a directory shadow" in
  Term.(ret (pure Lwt_main.run $ (pure shadow_directory $ convergence $ capability 0))),
  Term.info "shadow-directory" ~doc ~docs

let create_checkpoint_cmd =
  let doc = "create a checkpoint" in
  Term.(ret (pure Lwt_main.run $ (pure create_checkpoint $ convergence $ capability 0))),
  Term.info "create-checkpoint" ~doc ~docs

let show_checkpoint_cmd =
  let doc = "show checkpoint properties" in
  Term.(ret (pure Lwt_main.run $ (pure show_checkpoint $ digest 0))),
  Term.info "show-checkpoint" ~doc ~docs

let default_cmd =
  let doc = "command-line interface for Cylinder" in
  let man = [
    `S "BUGS";
    `P "Report bugs at http://github.com/whitequark/cylinder/issues.";
  ] in
  Term.(ret (pure (`Help (`Pager, None)))),
  Term.info "cylinder-cli" ~version:"0.1" ~doc ~man

let commands = [
    in_memory_server_cmd;
    init_client_cmd;
    get_block_cmd; put_block_cmd;
    show_chunk_cmd;
    show_data_cmd; retrieve_data_cmd; store_data_cmd;
    show_shadow_cmd;
    show_file_cmd; retrieve_file_cmd; store_file_cmd;
    store_directory_cmd; retrieve_directory_cmd;
    shadow_file_cmd; shadow_directory_cmd;
    create_checkpoint_cmd; show_checkpoint_cmd;
  ]

let () =
  match Term.eval_choice default_cmd commands with
  | `Error _ -> exit 1
  | _ -> exit 0
