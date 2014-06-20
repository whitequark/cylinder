let (>>=) = Lwt.(>>=)
let (>|=) = Lwt.(>|=)

let max_size = 10_000_000

type algorithm =
[ `SHA512_XSalsa20_Poly1305 [@key 1] ]
[@@protobuf]

let algorithm_to_string algo =
  match algo with
  | `SHA512_XSalsa20_Poly1305 -> "SHA512-XSalsa20-Poly1305"

let algorithm_of_string str =
  match str with
  | "SHA512-XSalsa20-Poly1305" -> Some `SHA512_XSalsa20_Poly1305
  | _ -> None

type 'a capability =
| Inline [@key 1] of bytes
| Stored [@key 2] of handle
and handle = {
  digest    : Block.digest  [@key 1];
  algorithm : algorithm     [@key 2] [@bare];
  key       : bytes         [@key 3];
}
[@@protobuf]

let capability_from_protobuf_ decoder =
  capability_from_protobuf (fun _ -> assert false) decoder
let capability_to_protobuf_ data encoder =
  capability_to_protobuf (fun _ -> assert false) data encoder

let section = Lwt_log.Section.make "Chunk"

let inspect_capability capa =
  match capa with
  | Inline bytes -> Printf.sprintf "inline:%S" bytes
  | Stored { digest } ->
    Printf.sprintf "stored:%s" (Block.inspect_digest digest)

let capability_digest capa =
  match capa with
  | Inline _ -> None
  | Stored { digest } -> Some digest

let capability_to_string capa =
  Base64_url.encode (Protobuf.Encoder.encode_exn capability_to_protobuf_ capa)

let capability_of_string str =
  match Base64_url.decode str with
  | Some x -> Protobuf.Decoder.decode capability_from_protobuf_ x
  | None   -> None

let capability_of_data ~encoder ~convergence data =
  let chunk_clear = Protobuf.Encoder.encode_exn encoder data in
  if Bytes.length chunk_clear < 128 then
    Lwt.return (Inline chunk_clear, None)
  else
    () |> Lwt_preemptive.detach (fun () ->
      let chunk_hash  = Sodium.Hash.Bytes.(of_hash (digest chunk_clear)) in
      let convg_hash  = Sodium.Hash.Bytes.(of_hash (digest
                                (Bytes.concat Bytes.empty [convergence; chunk_hash]))) in
      let sbox_key    = Sodium.Secret_box.Bytes.to_key (Bytes.sub convg_hash 0 32) in
      let sbox_nonce  = Sodium.Secret_box.Bytes.to_nonce (Bytes.sub convg_hash 32 24) in
      let chunk_enc   = Sodium.Secret_box.Bytes.secret_box sbox_key chunk_clear sbox_nonce in
      let chunk_key   = Bytes.sub convg_hash 0 56 in
      let digest      = Block.digest_bytes chunk_enc in
      Stored { digest; algorithm = `SHA512_XSalsa20_Poly1305; key = chunk_key }, Some chunk_enc)

let capability_to_data ~decoder capa chunk_enc =
  match capa, chunk_enc with
  | Stored { algorithm = `SHA512_XSalsa20_Poly1305; key }, Some chunk_enc ->
    () |> Lwt_preemptive.detach (fun () ->
      let sbox_key, sbox_nonce = Bytes.(sub key 0 32, sub key 32 24) in
      let sbox_key, sbox_nonce = Sodium.Secret_box.Bytes.(to_key sbox_key, to_nonce sbox_nonce) in
      try
        let chunk_clear = Sodium.Secret_box.Bytes.secret_box_open sbox_key chunk_enc sbox_nonce in
        `Ok (Protobuf.Decoder.decode_exn decoder chunk_clear)
      with Sodium.Verification_failure | Protobuf.Decoder.Failure _ ->
        `Malformed)
  | Inline chunk_clear, None ->
    begin try%lwt
      Lwt.return (`Ok (Protobuf.Decoder.decode_exn decoder chunk_clear))
    with Protobuf.Decoder.Failure _ ->
      Lwt.return `Malformed
    end
  | _ -> Lwt.return `Malformed

let store_data ~encoder ~convergence client data =
  match%lwt capability_of_data ~convergence ~encoder data with
  | (Inline _) as capa, None ->
    Lwt_log.debug_f ~section "inline: %s" (inspect_capability capa) >>
    Lwt.return (`Ok capa)
  | Stored { digest = (digest_kind, _) as digest } as capa, Some bytes ->
    begin match%lwt Block.Client.exists client digest with
    | `Not_found ->
      begin match%lwt Block.Client.put client digest_kind bytes with
      | (`Unavailable | `Not_supported) as result -> Lwt.return result
      | `Ok ->
        Lwt_log.debug_f ~section "uploaded: %s" (inspect_capability capa) >>
        Lwt.return (`Ok capa)
      end
    | `Unavailable as result -> Lwt.return result
    | `Ok ->
      Lwt_log.debug_f ~section "exists: %s" (inspect_capability capa) >>
      Lwt.return (`Ok capa)
    end
  | _ -> assert false

let retrieve_data ~decoder client capa =
  Lwt_log.debug_f ~section "retrieve: %s" (inspect_capability capa) >>
  match capa with
  | Inline _ -> capability_to_data ~decoder capa None
  | Stored { digest } ->
    match%lwt Block.Client.get client digest with
    | `Ok bytes -> capability_to_data ~decoder capa (Some bytes)
    | (`Not_found | `Unavailable | `Malformed) as err -> Lwt.return err
