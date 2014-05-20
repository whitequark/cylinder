let (>>=) = Lwt.(>>=)

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
      Lwt.return (`Ok (Unix.string_of_inet_addr addr, port))
    | {ai_family = PF_INET6; ai_addr = ADDR_INET(addr, port)}::_ ->
      Lwt.return (`Ok ("[" ^ (Unix.string_of_inet_addr addr) ^ "]", port))
    | _ :: rest -> find_addr rest
    | [] -> Lwt.return (`Error (false, Printf.sprintf "cannot resolve %s:%s" host service))
  in
  getprotobyname "tcp" >>= fun pe ->
  getaddrinfo host service [AI_PROTOCOL pe.p_proto] >>=
  find_addr

let load_server_config () =
  match Config.load ~app:"cylinder" ~name:"server.json"
                    ~loader:Server_config.server_config_of_string with
  | None -> `Error (false, "No server configuration found.")
  | Some config -> `Ok config

let init_server_config () =
  let open Server_config in
  Config.init ~app:"cylinder" ~name:"server.json"
              ~loader:server_config_of_string
              ~dumper:server_config_to_string
              ~init:(fun () ->
    Lwt_log.ign_notice "Generating a new server key pair";
    let secret_key, public_key = Box.random_key_pair () in
    { secret_key; public_key })

let server backend_kind host port =
  let open Server_config in
  let config = init_server_config () in
  let listen socket  =
    match backend_kind with
    | In_memory_backend ->
      let module Server = Block.Server(In_memory_store) in
      let backend = In_memory_store.create () in
      Server.listen (Server.create backend socket)
  in
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
  match%lwt resolve host (string_of_int port) with
  | `Error err -> Lwt.return (`Error err)
  | `Ok (addr, port) ->
    try
      ZMQ.Socket.bind zsocket (Printf.sprintf "tcp://%s:%d" addr port);
      Lwt_log.notice_f "Listening at %s:%d..." addr port >>= fun () ->
      listen zsocket >>= fun () ->
      Lwt.return (`Ok ())
    with exn ->
      Lwt.return (`Error (false, Printf.sprintf "Cannot bind to %s:%d" addr port))

let load_client_config () =
  match Config.load ~app:"cylinder" ~name:"client.json"
                    ~loader:Client_config.client_config_of_string with
  | None ->
    `Error (false, "No client configuration found. Use the client-init command.")
  | Some config -> `Ok config

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
  match load_client_config () with
  | `Error err -> Lwt.return (`Error err)
  | `Ok config ->
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
    match%lwt resolve config.server_host (string_of_int config.server_port) with
    | `Error err -> Lwt.return (`Error err)
    | `Ok (addr, port) ->
      ZMQ.Socket.connect zsocket (Printf.sprintf "tcp://%s:%d" addr port);
      Lwt.return (`Ok (config, Block.Client.create zsocket))

let handle_error err =
  match err with
  | `Unavailable ->
    Lwt.return (`Error (false, "Blockserver is unavailable"))
  | `Not_supported ->
    Lwt.return (`Error (false, "Blockserver does not support this digest kind"))
  | `Not_found ->
    Lwt.return (`Error (false, "A requested block is missing"))
  | `Malformed ->
    Lwt.return (`Error (false, "Stored data is corrupted"))

let istream_of_filename filename =
  if filename = "-"
  then Lwt.return Lwt_io.stdin
  else Lwt_io.open_file ~mode:Lwt_io.input filename

let ostream_of_filename filename =
  if filename = "-"
  then Lwt.return Lwt_io.stdout
  else Lwt_io.open_file ~mode:Lwt_io.output filename

let get_block force digest =
  match%lwt connect () with
  | `Error err -> Lwt.return (`Error err)
  | `Ok (config, client) ->
    if not (Unix.isatty Unix.stdout) || force then
      match%lwt Block.Client.get client digest with
      | (`Not_found | `Unavailable | `Malformed) as err -> handle_error err
      | `Ok bytes ->
        print_bytes bytes; Lwt.return (`Ok ())
    else
      Lwt.return (`Error (false, "You are attempting to output binary data to a terminal. \
                                  This is inadvisable, as it may cause display problems. \
                                  Pass -f/--force if you really want to taste it firsthand."))

let put_block digest_kind filename =
  match%lwt connect () with
  | `Error err -> Lwt.return (`Error err)
  | `Ok (config, client) ->
    let%lwt data = istream_of_filename filename >>= Lwt_io.read in
    match%lwt Block.Client.put client digest_kind data with
    | (`Unavailable | `Not_supported) as err -> handle_error err
    | `Ok ->
      Lwt_io.printl (Block.digest_to_string (Block.digest_bytes data)) >>= fun () ->
      Lwt.return (`Ok ())

let show_chunk capa =
  match%lwt connect () with
  | `Error err -> Lwt.return (`Error err)
  | `Ok (config, client) ->
    match capa with
    | Chunk.Inline bytes ->
      Lwt_io.printl  "Type:      inline" >>= fun () ->
      Lwt_io.printlf "Length:    %d bytes" (Bytes.length bytes) >>= fun () ->
      Lwt.return (`Ok ())
    | Chunk.Stored { Chunk.digest; algorithm; key } ->
      Lwt_io.printl  "Type:      stored" >>= fun () ->
      Lwt_io.printlf "Algorithm: %s" (Chunk.algorithm_to_string algorithm) >>= fun () ->
      Lwt_io.printlf "Key:       %s" (Base64_url.encode key) >>= fun () ->
      Lwt_io.printlf "Digest:    %s" (Block.digest_to_string digest) >>= fun () ->
      match%lwt Chunk.retrieve_chunk client capa with
      | (`Not_found | `Unavailable | `Malformed ) as err -> handle_error err
      | `Ok { Chunk.encoding; content } ->
        Lwt_io.printlf "Encoding:  %s" (Chunk.encoding_to_string encoding) >>= fun () ->
        Lwt_io.printlf "Length:    %d bytes" (Bytes.length content) >>= fun () ->
        Lwt.return (`Ok ())

let store_chunk convergence filename =
  match%lwt connect () with
  | `Error err -> Lwt.return (`Error err)
  | `Ok (config, client) ->
    let%lwt data = istream_of_filename filename >>= Lwt_io.read in
    let%lwt capa, bytes_opt = Chunk.capability_of_chunk ~convergence (Chunk.chunk_of_bytes data) in
    match%lwt Chunk.store_chunk client (capa, bytes_opt) with
    | (`Unavailable | `Not_supported | `Malformed) as err -> handle_error err
    | `Ok ->
      Lwt_io.printl (Chunk.capability_to_string capa) >>= fun () ->
      Lwt.return (`Ok ())

let retrieve_chunk capa filename =
  match%lwt connect () with
  | `Error err -> Lwt.return (`Error err)
  | `Ok (config, client) ->
    match%lwt Chunk.retrieve_chunk client capa with
    | (`Not_found | `Unavailable | `Malformed) as err -> handle_error err
    | `Ok chunk ->
      let%lwt stream = ostream_of_filename filename in
      Lwt_io.write stream (Chunk.chunk_to_bytes chunk) >>= fun () ->
      Lwt.return (`Ok ())

let show_graph_elt capa =
  match load_server_config () with
  | `Error err -> Lwt.return (`Error err)
  | `Ok server_config ->
    match%lwt connect () with
    | `Error err -> Lwt.return (`Error err)
    | `Ok (config, client) ->
      match%lwt Chunk.retrieve_chunk client capa with
      | (`Not_found | `Unavailable | `Malformed) as err -> handle_error err
      | `Ok chunk ->
        let bytes   = Chunk.chunk_to_bytes chunk in
        let decoder = Graph.element_from_protobuf (fun _ -> ()) in
        match Protobuf.Decoder.decode decoder bytes with
        | None -> Lwt.return (`Error (false, "Chunk does not contain a graph element"))
        | Some graph_elt ->
          match Graph.edge_list ~server:server_config.Server_config.secret_key graph_elt with
          | None -> Lwt.return (`Error (false, "Cannot decrypt graph element; wrong server?"))
          | Some digests ->
            digests |>
            List.map Block.digest_to_string |>
            Lwt_list.iter_s Lwt_io.printl >>= fun () ->
            Lwt.return (`Ok ())

let random_key () =
  let key = Secret_box.random_key () in
  Lwt_io.printl (Secret_box.key_to_string key) >>= fun () ->
  Lwt.return (`Ok ())

let unix_fd_of_filename filename mode =
  if filename = "-"
  then Lwt.return Lwt_unix.stdout
  else Lwt_unix.openfile filename mode 0o644

let get_file client digest key =
  match%lwt Block.Client.get client digest with
  | (`Not_found | `Unavailable | `Malformed) as err -> handle_error err
  | `Ok bytes ->
    let decoder = Secret_box.box_from_protobuf File.file_from_protobuf in
    match Protobuf.Decoder.decode (Graph.element_from_protobuf decoder) bytes with
    | None -> Lwt.return (`Error (false, "Block does not contain a graph element"))
    | Some graph_elt ->
      match Secret_box.decrypt graph_elt.Graph.content key with
      | None -> Lwt.return (`Error (false, "File metadata cannot be decrypted with provided key"))
      | Some file -> Lwt.return (`Ok file)

let show_file key digest =
  match%lwt connect () with
  | `Error err -> Lwt.return (`Error err)
  | `Ok (config, client) ->
    match%lwt get_file client digest key with
    | `Error err -> Lwt.return (`Error err)
    | `Ok file ->
      Lwt_io.printlf "Modified:   %s" (Timestamp.to_string file.File.last_modified) >>= fun () ->
      Lwt_io.printlf "Executable: %B" file.File.executable >>= fun () ->
      Lwt_io.printl  "Chunks:" >>= fun () ->
      file.File.chunks |> Lwt_list.iter_s (fun capa ->
        Lwt_io.printl (Chunk.capability_to_string capa)) >>= fun () ->
      Lwt.return (`Ok ())

let store_file key data =
  let open Client_config in
  match%lwt connect () with
  | `Error err -> Lwt.return (`Error err)
  | `Ok (config, client) ->
    let convergence = Protobuf.Encoder.encode_exn Secret_box.key_to_protobuf key in
    let%lwt fd = unix_fd_of_filename data Lwt_unix.[O_RDONLY] in
    match%lwt File.create_from_unix_fd ~convergence ~client fd with
    | (`Unavailable | `Not_supported) as err -> handle_error err
    | `Ok file ->
      let graph_elt = File.file_to_graph_elt
          ~server:config.server_key
          ~updater:(config.secret_key, config.public_key)
          ~key file in
      let encoder = Secret_box.box_to_protobuf File.file_to_protobuf in
      let bytes   = Protobuf.Encoder.encode_exn (Graph.element_to_protobuf encoder) graph_elt in
      let (kind, _) as digest = Block.digest_bytes bytes in
      match%lwt Block.Client.put client kind bytes with
      | (`Unavailable | `Not_supported) as err -> handle_error err
      | `Ok ->
        Lwt_io.printl (Block.digest_to_string digest) >>= fun () ->
        Lwt.return (`Ok ())

let retrieve_file key digest data =
  match%lwt connect () with
  | `Error err -> Lwt.return (`Error err)
  | `Ok (config, client) ->
    match%lwt get_file client digest key with
    | `Error err -> Lwt.return (`Error err)
    | `Ok file ->
      let%lwt fd = unix_fd_of_filename data Lwt_unix.[O_WRONLY; O_CREAT] in
      match%lwt File.retrieve_to_unix_fd ~client file fd with
      | (`Not_found | `Unavailable | `Malformed) as err -> handle_error err
      | `Ok -> Lwt.return (`Ok ())

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
  make_arg_conv Chunk.capability_of_string Chunk.capability_to_string
                "Invalid capability format"

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

let server_cmd =
  let backend =
    let doc = "Use $(docv) (one of: in-memory) for storing blocks." in
    let xs  = ["in-memory", Some In_memory_backend; "", None] in
    Arg.(required & pos 0 (enum xs) None & info [] ~docv:"BACKEND" ~doc)
  in
  let address =
    let doc = "Bind ZeroMQ socket to address $(docv)" in
    Arg.(value & opt string "*" & info ["b"; "bind-to"] ~docv:"ADDRESS" ~doc)
  in
  let port =
    let doc = "Bind ZeroMQ socket to port $(docv)" in
    Arg.(value & opt int 5555 & info ["p"; "port"] ~docv:"PORT" ~doc)
  in
  let doc = "run a server" in
  Term.(ret (pure Lwt_main.run $ (pure server $ backend $ address $ port))),
  Term.info "server" ~doc ~docs

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

let capability =
  let doc = "Retrieve chunk with capability $(docv)" in
  Arg.(required & pos 0 (some capability) None & info [] ~docv:"CAPABILITY" ~doc)

let show_chunk_cmd =
  let doc = "show chunk properties" in
  Term.(ret (pure Lwt_main.run $ (pure show_chunk $ capability))),
  Term.info "show-chunk" ~doc ~docs

let convergence =
  let doc = "Use specified convergence key (in RFC 4648 'base64url' format)" in
  Arg.(value & opt base64url "" & info ["c"; "convergence-key"] ~docv:"KEY" ~doc)

let store_chunk_cmd =
  let doc = "store chunk" in
  Term.(ret (pure Lwt_main.run $ (pure store_chunk $ convergence $ data_in 1))),
  Term.info "store-chunk" ~doc ~docs

let retrieve_chunk_cmd =
  let doc = "retrieve chunk" in
  Term.(ret (pure Lwt_main.run $ (pure retrieve_chunk $ capability $ data_out 1))),
  Term.info "retrieve-chunk" ~doc ~docs

let show_graph_elt_cmd =
  let doc = "show graph element properties" in
  Term.(ret (pure Lwt_main.run $ (pure show_graph_elt $ capability))),
  Term.info "show-graph-element" ~doc ~docs

let random_key_cmd =
  let doc = "generate a symmetric key" in
  Term.(ret (pure Lwt_main.run $ (pure random_key $ pure ()))),
  Term.info "random-key" ~doc ~docs

let checkpoint_key p =
  let doc = "Use checkpoint secret key $(docv)" in
  Arg.(required & pos p (some symmetric_key) None & info [] ~docv:"CKPOINT-KEY" ~doc)

let show_file_cmd =
  let doc = "show file" in
  Term.(ret (pure Lwt_main.run $ (pure show_file $ checkpoint_key 0 $ digest 1))),
  Term.info "show-file" ~doc ~docs

let store_file_cmd =
  let doc = "store file" in
  Term.(ret (pure Lwt_main.run $ (pure store_file $ checkpoint_key 0 $ data_in 1))),
  Term.info "store-file" ~doc ~docs

let retrieve_file_cmd =
  let doc = "retrieve file" in
  Term.(ret (pure Lwt_main.run $ (pure retrieve_file $ checkpoint_key 0 $ digest 1 $ data_out 2))),
  Term.info "retrieve-file" ~doc ~docs

let default_cmd =
  let doc = "command-line interface for Cylinder" in
  let man = [
    `S "BUGS";
    `P "Report bugs at http://github.com/whitequark/cylinder/issues.";
  ] in
  Term.(ret (pure (`Help (`Pager, None)))),
  Term.info "cylinder-cli" ~version:"0.1" ~doc ~man

let commands = [
    server_cmd;
    init_client_cmd;
    random_key_cmd;
    get_block_cmd; put_block_cmd;
    show_chunk_cmd; retrieve_chunk_cmd; store_chunk_cmd;
    show_graph_elt_cmd;
    show_file_cmd; retrieve_file_cmd; store_file_cmd;
  ]

let () =
  match Term.eval_choice default_cmd commands with
  | `Error _ -> exit 1
  | _ -> exit 0
