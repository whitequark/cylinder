type key = {
  algorithm : [ `XSalsa20_Poly1305 [@key 1] ] [@key 1];
  key       : bytes [@key 2];
} [@@protobuf]

let random_key () =
  { algorithm = `XSalsa20_Poly1305;
    key       = Sodium.Secret_box.(Bytes.of_key (random_key ())) }

type encrypted = {
  data      : bytes [@key 1];
  nonce     : bytes [@key 2];
} [@@protobuf]

type 'content box =
| Cleartext  of 'content  * key
| Ciphertext of encrypted * (Protobuf.Decoder.t -> 'content)

let box_from_protobuf content_from_protobuf decoder =
  let encrypted = encrypted_from_protobuf decoder in
  Ciphertext (encrypted, content_from_protobuf)

let box_to_protobuf content_to_protobuf box encoder =
  match box with
  | Ciphertext (encrypted, _) ->
    encrypted_to_protobuf encrypted encoder
  | Cleartext (content, { algorithm = `XSalsa20_Poly1305; key }) ->
    let key   = Sodium.Secret_box.Bytes.to_key key in
    let nonce = Sodium.Secret_box.random_nonce () in
    let clear_bytes = Protobuf.Encoder.encode_bytes content_to_protobuf content in
    let enc_bytes   = Sodium.Secret_box.Bytes.secret_box key clear_bytes nonce in
    let encrypted   = { data = enc_bytes; nonce = Sodium.Secret_box.Bytes.of_nonce nonce } in
    encrypted_to_protobuf encrypted encoder

let store content key =
  Cleartext (content, key)

let decrypt box key =
  match box with
  | Cleartext (content, key') when key = key' -> Some content
  | Cleartext _ -> None
  | Ciphertext ({ data = enc_bytes; nonce }, content_from_protobuf) ->
    match key with
    | { algorithm = `XSalsa20_Poly1305; key } ->
      let key   = Sodium.Secret_box.Bytes.to_key key in
      let nonce = Sodium.Secret_box.Bytes.to_nonce nonce in
      try
        let clear_bytes = Sodium.Secret_box.Bytes.secret_box_open key enc_bytes nonce in
        let content     = Protobuf.Decoder.decode_bytes content_from_protobuf clear_bytes in
        Some content
      with Sodium.Verification_failure ->
        None
