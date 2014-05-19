open OUnit2

module In_memory_server = Block.Server(In_memory_store)

let blockserver_setup ctxt =
  let backend = In_memory_store.create () in
  let sctx    = ZMQ.Context.create () in
  let sserver = ZMQ.Socket.create sctx ZMQ.Socket.router in
  ZMQ.Socket.bind sserver "tcp://127.0.0.1:5555";
  let server  = In_memory_server.create backend sserver in
  Lwt.async (fun () ->
    try%lwt In_memory_server.listen server
    with Unix.Unix_error(Unix.ENOTSOCK, _, _) -> Lwt.return_unit);
  let sclient = ZMQ.Socket.create sctx ZMQ.Socket.req in
  ZMQ.Socket.connect sclient "tcp://127.0.0.1:5555";
  let client  = Block.Client.create sclient in
  (backend, sctx, server, client)

let blockserver_teardown (backend, sctx, server, client) ctxt =
  ZMQ.Socket.close (In_memory_server.to_socket server);
  ZMQ.Socket.close (Block.Client.to_socket client);
  ZMQ.Context.terminate sctx

let blockserver_bracket = bracket blockserver_setup blockserver_teardown

let with_env var value f =
  let old_value = try Some (Unix.getenv var) with Not_found -> None in
  Unix.putenv var value;
  f ();
  match old_value with
  | Some old_value -> Unix.putenv var old_value
  | None -> ExtUnix.All.unsetenv var
