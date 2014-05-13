let (>|=) = Lwt.(>|=)

type chunk = {
  encoding  : [ `None [@key 1] | `LZ4 [@key 2] ]
                    [@key  1] [@default `None] [@bare];
  content   : bytes [@key 15];
}
[@@protobuf]

let chunk_of_bytes bytes =
  { encoding = `None; content = bytes }

let chunk_to_bytes chunk =
  match chunk with
  | { encoding = `None; content } -> content
  | _ -> assert false

type capability =
| Inline [@key 1] of bytes
| Stored [@key 2] of handle
and algorithm =
[ `SHA512_XSalsa20_Poly1305 [@key 1] ]
and handle = {
  digest    : Block.digest  [@key 1];
  algorithm : algorithm     [@key 2] [@bare];
  key       : bytes         [@key 3];
}
[@@protobuf]

let capability_of_chunk ~convergence chunk =
  let chunk_clear = Protobuf.Encoder.encode_bytes chunk_to_protobuf chunk in
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

let capability_to_chunk capa data =
  match capa, data with
  | Stored { algorithm = `SHA512_XSalsa20_Poly1305; key }, Some chunk_enc ->
    () |> Lwt_preemptive.detach (fun () ->
      let sbox_key, sbox_nonce = Bytes.(sub key 0 32, sub key 32 24) in
      let sbox_key, sbox_nonce = Sodium.Secret_box.Bytes.(to_key sbox_key, to_nonce sbox_nonce) in
      try
        let chunk_clear = Sodium.Secret_box.Bytes.secret_box_open sbox_key chunk_enc sbox_nonce in
        `Ok (Protobuf.Decoder.decode_bytes chunk_from_protobuf chunk_clear)
      with Sodium.Verification_failure ->
        `Malformed)
  | Inline chunk_clear, None ->
    Lwt.return (`Ok (Protobuf.Decoder.decode_bytes chunk_from_protobuf chunk_clear))
  | _ -> Lwt.return `Malformed

let retrieve_chunk client capa =
  match capa with
  | Inline _ -> capability_to_chunk capa None
  | Stored { digest } ->
    match%lwt Block.Client.get client digest with
    | `Ok bytes -> capability_to_chunk capa (Some bytes)
    | (`Not_found | `Unavailable) as err -> Lwt.return err

let store_chunk client input =
  match input with
  | Inline _, None -> Lwt.return `Ok
  | Stored { digest = (digest_kind, _) }, Some bytes ->
    begin match%lwt Block.Client.put client digest_kind bytes with
    | (`Ok | `Unavailable | `Not_supported) as result -> Lwt.return result
    end
  | _ -> Lwt.return `Malformed
