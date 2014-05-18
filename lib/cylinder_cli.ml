open Cmdliner

let (>>=) = Lwt.(>>=)

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

let server_cmd =
  let backend =
    let doc = "Use $(docv) (in-memory) for storing blocks." in
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
  Term.info "server" ~doc

let default_cmd =
  let doc = "command-line interface for Cylinder" in
  let man = [
    `S "BUGS";
    `P "Report bugs at http://github.com/whitequark/cylinder/issues.";
  ] in
  Term.(ret (pure (`Help (`Pager, None)))),
  Term.info "cylinder-cli" ~version:"0.1" ~doc ~man

let () =
  match Term.eval_choice default_cmd [server_cmd] with
  | `Error _ -> exit 1
  | _ -> exit 0
