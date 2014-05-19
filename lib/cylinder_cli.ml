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
    | `Not_found ->
      Lwt.return (`Error (false, Printf.sprintf "Block is not found"))
    | `Unavailable ->
      Lwt.return (`Error (false, "Blockserver is unavailable"))

let put_block client_opts digest_kind data =
  let client = connect client_opts in
  let%lwt file =
    if data = "-"
    then Lwt.return Lwt_io.stdin
    else Lwt_io.open_file ~mode:Lwt_io.input data
  in
  let%lwt data = Lwt_io.read file in
  match%lwt Block.Client.put client digest_kind data with
  | `Ok ->
    Lwt_io.printl (Block.digest_to_string (Block.digest_bytes data)) >>= fun () ->
    Lwt.return (`Ok ())
  | `Unavailable ->
    Lwt.return (`Error (false, "Blockserver is unavailable"))
  | `Not_supported ->
    Lwt.return (`Error (false, "Blockserver does not support this digest kind"))

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

let put_block_cmd =
  let data =
    let doc = "Read data from file $(docv), or stdin if $(docv) is \"-\"" in
    Arg.(value & pos 0 string "-" & info [] ~docv:"DATA" ~doc)
  in
  let digest_kind =
    let doc = "Store block with digest kind $(docv) (one of: sha512)" in
    Arg.(value & opt digest_kind `SHA512 & info ["k"; "kind"] ~docv:"KIND" ~doc)
  in
  let doc = "store a block" in
  Term.(ret (pure Lwt_main.run $ (pure put_block $ client_opts_t $ digest_kind $ data))),
  Term.info "put-block" ~doc ~docs

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
  ]

let () =
  match Term.eval_choice default_cmd commands with
  | `Error _ -> exit 1
  | _ -> exit 0
