open OUnit2

let (>>=) = Lwt.(>>=)

let with_env var value f =
  let old_value = try Some (Unix.getenv var) with Not_found -> None in
  Unix.putenv var value;
  f ();
  match old_value with
  | Some old_value -> Unix.putenv var old_value
  | None -> ExtUnix.All.unsetenv var

module In_memory_server = Block.Server(In_memory_store)

let blockserver_setup ctxt =
  let backend = In_memory_store.create () in
  let sctx    = ZMQ.Context.create () in
  let sserver = ZMQ.Socket.create sctx ZMQ.Socket.router in
  ZMQ.Socket.set_max_message_size sserver Block.max_message_size;
  ZMQ.Socket.bind sserver "tcp://127.0.0.1:5555";
  let server  = In_memory_server.create backend sserver in
  Lwt.async (fun () ->
    try%lwt In_memory_server.listen server
    with Unix.Unix_error(Unix.ENOTSOCK, _, _) -> Lwt.return_unit);
  let sclient = ZMQ.Socket.create sctx ZMQ.Socket.req in
  ZMQ.Socket.set_max_message_size sclient Block.max_message_size;
  ZMQ.Socket.connect sclient "tcp://127.0.0.1:5555";
  let client  = Block.Client.create sclient in
  (backend, sctx, server, client)

let blockserver_teardown (backend, sctx, server, client) ctxt =
  ZMQ.Socket.close (In_memory_server.to_socket server);
  ZMQ.Socket.close (Block.Client.to_socket client);
  ZMQ.Context.terminate sctx

let blockserver_bracket = bracket blockserver_setup blockserver_teardown

let tmpdata_bracket ctxt data =
  let filename, outch = bracket_tmpfile ctxt in
  output_string outch data; flush outch; close_out outch;
  Lwt_unix.openfile filename [Lwt_unix.O_RDWR] 0

let get_chunk ~decoder client capa =
  match%lwt Chunk.retrieve_data ~decoder client capa with
  | `Ok data -> Lwt.return data
  | _ -> assert_failure "Chunk.retrieve_data"

let put_chunk ?(convergence="") ~encoder client data =
  match%lwt Chunk.store_data ~convergence ~encoder client data with
  | `Ok capa -> Lwt.return capa
  | _ -> assert_failure "Chunk.store_data"

let write_file path data =
  let%lwt chan = Lwt_io.open_file Lwt_io.output path in
  Lwt_io.write chan data >>= fun () ->
  Lwt_io.close chan
