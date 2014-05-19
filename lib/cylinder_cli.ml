open Cmdliner

let (>>=) = Lwt.(>>=)

(* Command implementation *)

type backend_kind = In_memory_backend

let server backend_kind addr port =
  let server socket =
    match backend_kind with
    | In_memory_backend ->
      let module Server = Block.Server(In_memory_store) in
      let backend = In_memory_store.create () in
      Server.listen (Server.create backend socket)
  in
  let zcontext = ZMQ.Context.create () in
  let zsocket  = ZMQ.Socket.create zcontext ZMQ.Socket.router in
  ZMQ.Socket.bind zsocket (Printf.sprintf "tcp://%s:%d" addr port);
  Lwt_main.run (
    Lwt_log.notice_f "Listening at %s:%d..." addr port >>= fun () ->
    server zsocket)

type client_opts = {
  address : string;
  port    : int;
}

let connect { address; port } =
  let zcontext = ZMQ.Context.create () in
  let zsocket  = ZMQ.Socket.create zcontext ZMQ.Socket.req in
  ZMQ.Socket.connect zsocket (Printf.sprintf "tcp://%s:%d" address port);
  Block.Client.create zsocket

let handle_error err =
  match err with
  | `Not_found ->
    Lwt.return (`Error (false, "Block is not found"))
  | `Unavailable ->
    Lwt.return (`Error (false, "Blockserver is unavailable"))
  | `Not_supported ->
    Lwt.return (`Error (false, "Blockserver does not support this digest kind"))
  | `Malformed ->
    Lwt.return (`Error (false, "Capability or chunk are malformed"))

let get_block client_opts force digest =
  let client = connect client_opts in
  if Unix.isatty Unix.stdout && not force then
    Lwt.return (`Error (false, "You are attempting to output binary data to a terminal. \
                                This is inadvisable, as it may cause display problems. \
                                Pass -f/--force if you really want to taste it firsthand."))
  else
    match%lwt Block.Client.get client digest with
    | `Ok bytes ->
      print_bytes bytes; Lwt.return (`Ok ())
    | (`Not_found | `Unavailable) as err -> handle_error err

let stream_of_filename filename =
  if filename = "-"
  then Lwt.return Lwt_io.stdin
  else Lwt_io.open_file ~mode:Lwt_io.input filename

let put_block client_opts digest_kind filename =
  let client = connect client_opts in
  let%lwt data = stream_of_filename filename >>= Lwt_io.read in
  match%lwt Block.Client.put client digest_kind data with
  | `Ok ->
    Lwt_io.printl (Block.digest_to_string (Block.digest_bytes data)) >>= fun () ->
    Lwt.return (`Ok ())
  | (`Unavailable | `Not_supported) as err -> handle_error err

let show_chunk client_opts capa =
  let client = connect client_opts in
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
    | `Ok { Chunk.encoding; content } ->
      Lwt_io.printlf "Encoding:  %s" (Chunk.encoding_to_string encoding) >>= fun () ->
      Lwt_io.printlf "Length:    %d bytes" (Bytes.length content) >>= fun () ->
      Lwt.return (`Ok ())
    | (`Not_found | `Unavailable | `Malformed ) as err -> handle_error err

let store_chunk client_opts convergence filename =
  let client = connect client_opts in
  let%lwt data = stream_of_filename filename >>= Lwt_io.read in
  let%lwt capa, bytes_opt = Chunk.capability_of_chunk ~convergence (Chunk.chunk_of_bytes data) in
  match%lwt Chunk.store_chunk client (capa, bytes_opt) with
  | `Ok ->
    Lwt_io.printl (Chunk.capability_to_string capa) >>= fun () ->
    Lwt.return (`Ok ())
  | (`Unavailable | `Not_supported | `Malformed) as err -> handle_error err

let retrieve_chunk client_opts capa =
  let client = connect client_opts in
  match%lwt Chunk.retrieve_chunk client capa with
  | `Ok chunk ->
    Lwt_io.print (Chunk.chunk_to_bytes chunk) >>= fun () ->
    Lwt.return (`Ok ())
  | (`Not_found | `Unavailable | `Malformed) as err -> handle_error err

(* Command specification *)

let digest_kind =
  (fun str ->
    match Block.digest_kind_of_string str with
    | Some x -> `Ok x | None -> `Error "Invalid digest kind format"),
  (fun fmt digest ->
    Format.pp_print_string fmt (Block.digest_kind_to_string digest))

let digest =
  (fun str ->
    match Block.digest_of_string str with
    | Some x -> `Ok x | None -> `Error "Invalid digest format"),
  (fun fmt digest ->
    Format.pp_print_string fmt (Block.digest_to_string digest))

let capability =
  (fun str ->
    match Chunk.capability_of_string str with
    | Some x -> `Ok x | None -> `Error "Invalid capability format"),
  (fun fmt digest ->
    Format.pp_print_string fmt (Chunk.capability_to_string digest))

let base64url =
  (fun str ->
    match Base64_url.decode str with
    | Some x -> `Ok x | None -> `Error "Invalid base64url encoding"),
  (fun fmt bytes ->
    Format.pp_print_string fmt (Base64_url.encode bytes))

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
  Term.(pure server $ backend $ address $ port),
  Term.info "server" ~doc ~docs

let docs = "LOW-LEVEL COMMANDS"

let client_opts address port = { address; port }
let client_opts_t =
  let address =
    let doc = "Connect to address $(docv)" in
    Arg.(value & opt string "127.0.0.1" & info ["a"; "address"] ~docv:"ADDRESS" ~doc)
  in
  let port =
    let doc = "Connect to port $(docv)" in
    Arg.(value & opt int 5555 & info ["p"; "port"] ~docv:"PORT" ~doc)
  in
  Term.(pure client_opts $ address $ port)

let force =
  let doc = "Output raw data to terminal" in
  Arg.(value & flag & info ["f"; "force"] ~doc)

let get_block_cmd =
  let digest =
    let doc = "Retrieve block with digest $(docv)" in
    Arg.(required & pos 0 (some digest) None & info [] ~docv:"DIGEST" ~doc)
  in
  let doc = "retrieve a block" in
  Term.(ret (pure Lwt_main.run $ (pure get_block $ client_opts_t $ force $ digest))),
  Term.info "get-block" ~doc ~docs

let data =
  let doc = "Read data from file $(docv), or stdin if $(docv) is \"-\"" in
  Arg.(value & pos 0 string "-" & info [] ~docv:"DATA" ~doc)

let put_block_cmd =
  let digest_kind =
    let doc = "Store block with digest kind $(docv) (one of: sha512)" in
    Arg.(value & opt digest_kind `SHA512 & info ["k"; "kind"] ~docv:"KIND" ~doc)
  in
  let doc = "store a block" in
  Term.(ret (pure Lwt_main.run $ (pure put_block $ client_opts_t $ digest_kind $ data))),
  Term.info "put-block" ~doc ~docs

let capability =
  let doc = "Retrieve chunk with capability $(docv)" in
  Arg.(required & pos 0 (some capability) None & info [] ~docv:"CAPABILITY" ~doc)

let show_chunk_cmd =
  let doc = "show chunk properties" in
  Term.(ret (pure Lwt_main.run $ (pure show_chunk $ client_opts_t $ capability))),
  Term.info "show-chunk" ~doc ~docs

let convergence =
  let doc = "Use specified convergence key (in RFC 4648 'base64url' format)" in
  Arg.(value & opt base64url "" & info ["c"; "convergence-key"] ~docv:"KEY" ~doc)

let store_chunk_cmd =
  let doc = "store chunk" in
  Term.(ret (pure Lwt_main.run $ (pure store_chunk $ client_opts_t $ convergence $ data))),
  Term.info "store-chunk" ~doc ~docs

let retrieve_chunk_cmd =
  let doc = "retrieve chunk" in
  Term.(ret (pure Lwt_main.run $ (pure retrieve_chunk $ client_opts_t $ capability))),
  Term.info "retrieve-chunk" ~doc ~docs

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
    get_block_cmd; put_block_cmd;
    show_chunk_cmd; retrieve_chunk_cmd; store_chunk_cmd;
  ]

let () =
  match Term.eval_choice default_cmd commands with
  | `Error _ -> exit 1
  | _ -> exit 0
