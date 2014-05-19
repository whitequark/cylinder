let (>>=) = Lwt.(>>=)
let (>|=) = Lwt.(>|=)

type digest_kind = [ `SHA512 [@key 1] ]
[@@protobuf]

let digest_kind_to_string digest_kind =
  match digest_kind with
  | `SHA512 -> "sha512"

let digest_kind_of_string str =
  match str with
  | "sha512" -> Some `SHA512
  | _ -> None

type digest = digest_kind [@bare] * string
[@@protobuf]

let digest_bytes bytes =
  `SHA512, Bytes.to_string (Sodium.Hash.Bytes.of_hash (Sodium.Hash.Bytes.digest bytes))

let digest_bigbytes bytes =
  `SHA512, Bytes.to_string (Sodium.Hash.Bytes.of_hash (Sodium.Hash.Bigbytes.digest bytes))

let digest_to_string digest =
  Base64_url.encode (Protobuf.Encoder.encode_exn digest_to_protobuf digest)

let digest_of_string str =
  match Base64_url.decode str with
  | Some x -> Protobuf.Decoder.decode digest_from_protobuf x
  | None   -> None

let inspect_digest digest =
  (String.sub (digest_to_string digest) 0 10) ^ "..."

module type BACKEND = sig
  type t

  val get       : t -> digest -> [> `Ok of string | `Not_found | `Unavailable ] Lwt.t
  val put       : t -> digest -> string -> [> `Ok | `Unavailable ] Lwt.t
  val erase     : t -> digest -> unit Lwt.t
  val enumerate : t -> string -> [ `Ok of (string * digest list) | `Exhausted ] Lwt.t
end

module Protocol = struct
  type request =
  [ `Get            [@key 1] of digest
  | `Put            [@key 2] of digest_kind [@bare] * bytes
  | `Erase          [@key 3] of digest
  | `Enumerate      [@key 4] of string
  ] [@@protobuf]

  let shorten bytes =
    if Bytes.length bytes < 10
    then Printf.sprintf "%S" (Bytes.to_string bytes)
    else Printf.sprintf "%S..." (Bytes.sub_string bytes 0 10)

  let request_to_string req =
    match req with
    | `Get digest ->
      Printf.sprintf "`Get %s" (inspect_digest digest)
    | `Put (`SHA512, obj) ->
      Printf.sprintf "`Put (`SHA512, %s)" (shorten obj)
    | `Erase digest ->
      Printf.sprintf "`Erase %s" (inspect_digest digest)
    | `Enumerate cookie ->
      Printf.sprintf "`Enumerate %S" cookie

  type get_response =
  [ `Ok             [@key 1] of bytes
  | `Not_found      [@key 2]
  | `Unavailable    [@key 3]
  ] [@@protobuf]

  let get_response_to_string resp =
    match resp with
    | `Ok bytes -> Printf.sprintf "`Ok %s..." (shorten bytes)
    | `Not_found -> "`Not_found"
    | `Unavailable -> "`Unavailable"

  type put_response =
  [ `Ok             [@key 1]
  | `Unavailable    [@key 2]
  | `Not_supported  [@key 3]
  ] [@@protobuf]

  let put_response_to_string resp =
    match resp with
    | `Ok -> "`Ok"
    | `Unavailable -> "`Unavailable"
    | `Not_supported -> "`Not_supported"

  type erase_response =
  [ `Ok             [@key 1]
  | `Forbidden      [@key 2]
  ] [@@protobuf]

  let erase_response_to_string resp =
    match resp with
    | `Ok -> "`Ok"
    | `Forbidden -> "`Forbidden"

  type enumerate_response =
  [ `Ok             [@key 1] of string * digest list
  | `Exhausted      [@key 2]
  | `Forbidden      [@key 3]
  ] [@@protobuf]

  let enumerate_response_to_string resp =
    match resp with
    | `Ok (cookie, digests) ->
      Printf.sprintf "`Ok (%S, [%s])"
                     cookie (String.concat "; " (List.map inspect_digest digests))
    | `Exhausted -> "`Exhausted"
    | `Forbidden -> "`Forbidden"
end

module Server(Backend: BACKEND) = struct
  type t = {
    backend : Backend.t;
    socket  : [`Router] Lwt_zmq.Socket.t;
  }

  let section = Lwt_log.Section.make "Blockserver"

  let create backend socket =
    ZMQ.Socket.set_max_message_size socket 16_777_211; (* max_string_length on 32-bit *)
    { backend; socket = Lwt_zmq.Socket.of_socket socket }

  let to_socket { socket } =
    Lwt_zmq.Socket.to_socket socket

  let handle server id request =
    let open Protocol in
    try%lwt
      let request = Protobuf.Decoder.decode_exn request_from_protobuf request in
      Lwt_log.debug ~section (Protocol.request_to_string request) >>= fun () ->
      begin match request with
      | `Get digest ->
        Backend.get server.backend digest >>= fun response ->
        Lwt_log.debug ~section (Protocol.get_response_to_string response) >>= fun () ->
        Lwt.return (Protobuf.Encoder.encode_exn get_response_to_protobuf response)

      | `Put (digest_kind, data) ->
        begin match digest_kind with
        | `SHA512 -> (* This should list only known secure hash functions. *)
          let (digest_kind', _) as digest = digest_bytes data in
          if digest_kind' <> digest_kind then
            Lwt.return `Not_supported
          else
            Backend.put server.backend digest data
        end >>= fun response ->
        Lwt_log.debug ~section (Protocol.put_response_to_string response) >>= fun () ->
        Lwt.return (Protobuf.Encoder.encode_exn put_response_to_protobuf response)

      | `Erase digest ->
        (* TODO check auth; needs libzmq support *)
        Backend.erase server.backend digest >>= fun () ->
        Lwt.return `Ok >>= fun response ->
        Lwt_log.debug ~section (Protocol.erase_response_to_string response) >>= fun () ->
        Lwt.return (Protobuf.Encoder.encode_exn erase_response_to_protobuf response)

      | `Enumerate cookie ->
        (* TODO check auth; needs libzmq support *)
        Backend.enumerate server.backend cookie >>= fun response ->
        Lwt_log.debug ~section (Protocol.enumerate_response_to_string response) >>= fun () ->
        Lwt.return (Protobuf.Encoder.encode_exn enumerate_response_to_protobuf response)

      end >>= fun reply ->
      Lwt_zmq.Socket.Router.send server.socket id [""; reply]
    with (Protobuf.Decoder.Failure _ as exn) ->
      Lwt_log.notice_f ~section ~exn "%S: Decoder failure: " (id :> string)

  let rec listen server =
    match%lwt Lwt_zmq.Socket.Router.recv server.socket with
    | (id, [""; request]) ->
      Lwt.join [handle server id request; listen server]
    | (id, _) ->
      Lwt_log.notice_f ~section "%S: Malformed packet" (id :> string) >>= fun () ->
      listen server
end

module Client = struct
  type t = [`Req] Lwt_zmq.Socket.t

  let section = Lwt_log.Section.make "Blockclient"

  let create socket =
    ZMQ.Socket.set_max_message_size socket 16_777_211; (* max_string_length on 32-bit *)
    Lwt_zmq.Socket.of_socket socket

  let to_socket socket =
    Lwt_zmq.Socket.to_socket socket

  let roundtrip socket decoder stringifier request =
    Lwt_log.debug ~section (Protocol.request_to_string request) >>= fun () ->
    let message = Protobuf.Encoder.encode_exn Protocol.request_to_protobuf request in
    Lwt_zmq.Socket.send socket message >>= fun () ->
    Lwt_zmq.Socket.recv socket >>= fun message' ->
    try
      let response = Protobuf.Decoder.decode_exn decoder message' in
      Lwt_log.debug ~section (stringifier response) >>= fun () ->
      Lwt.return response
    with exn ->
      Lwt_log.notice_f ~section ~exn "Decoder failure: " >>= fun () ->
      Lwt.fail exn

  let get socket digest =
    roundtrip socket Protocol.get_response_from_protobuf Protocol.get_response_to_string
              (`Get digest)

  let put socket digest_kind obj =
    roundtrip socket Protocol.put_response_from_protobuf Protocol.put_response_to_string
              (`Put (digest_kind, obj))

  let erase socket digest =
    roundtrip socket Protocol.erase_response_from_protobuf Protocol.erase_response_to_string
              (`Erase digest)

  let enumerate socket cookie =
    roundtrip socket Protocol.enumerate_response_from_protobuf Protocol.enumerate_response_to_string
              (`Enumerate cookie)

  let digests socket =
    match%lwt enumerate socket "" with
    | `Forbidden as x -> Lwt.return x
    | `Exhausted -> Lwt.return (`Ok (Lwt_stream.of_list []))
    | `Ok (cookie, digests) ->
      let cookie = ref cookie in
      let stream = Lwt_stream.from (fun () ->
        match%lwt enumerate socket !cookie with
        | `Ok (cookie', digests) -> cookie := cookie'; Lwt.return (Some digests)
        | `Exhausted -> Lwt.return_none
        | `Forbidden -> assert false)
      in
      Lwt.return (`Ok (Lwt_stream.append (Lwt_stream.of_list digests)
                                         (Lwt_stream.flatten stream)))
end
