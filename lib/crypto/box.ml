type key = {
  algorithm : [ `Curve25519_XSalsa20_Poly1305 [@key 1] ] [@key 1];
  key       : bytes [@key 2];
} [@@protobuf]

type public_key = key
type secret_key = key
type key_pair = secret_key * public_key

let public_key_from_protobuf = key_from_protobuf
let public_key_to_protobuf = key_to_protobuf

let secret_key_from_protobuf = key_from_protobuf
let secret_key_to_protobuf = key_to_protobuf

let random_key_pair () =
  let sk, pk = Sodium.Box.random_keypair () in
  { algorithm = `Curve25519_XSalsa20_Poly1305;
    key       = Sodium.Box.Bytes.of_secret_key sk },
  { algorithm = `Curve25519_XSalsa20_Poly1305;
    key       = Sodium.Box.Bytes.of_public_key pk }

type encrypted = {
  data      : bytes [@key 1];
  nonce     : bytes [@key 2];
} [@@protobuf]

type 'content box =
| Cleartext  of 'content  * secret_key * public_key
| Ciphertext of encrypted * (Protobuf.Decoder.t -> 'content)

let encrypt clear_bytes secret_key public_key =
  match secret_key, public_key with
  | { algorithm = `Curve25519_XSalsa20_Poly1305; key = secret_key },
    { algorithm = `Curve25519_XSalsa20_Poly1305; key = public_key } ->
    let secret_key  = Sodium.Box.Bytes.to_secret_key secret_key in
    let public_key  = Sodium.Box.Bytes.to_public_key public_key in
    let nonce       = Sodium.Box.random_nonce () in
    let enc_bytes   = Sodium.Box.Bytes.box secret_key public_key clear_bytes nonce in
    { data = enc_bytes; nonce = Sodium.Box.Bytes.of_nonce nonce }

let decrypt encrypted secret_key public_key =
  let { data = enc_bytes; nonce } = encrypted in
  match secret_key, public_key with
  | { algorithm = `Curve25519_XSalsa20_Poly1305; key = secret_key },
    { algorithm = `Curve25519_XSalsa20_Poly1305; key = public_key } ->
    let secret_key = Sodium.Box.Bytes.to_secret_key secret_key in
    let public_key = Sodium.Box.Bytes.to_public_key public_key in
    let nonce      = Sodium.Box.Bytes.to_nonce nonce in
    try
      let clear_bytes = Sodium.Box.Bytes.box_open secret_key public_key enc_bytes nonce in
      Some clear_bytes
    with Sodium.Verification_failure ->
      None

let box_from_protobuf content_from_protobuf decoder =
  let encrypted = encrypted_from_protobuf decoder in
  Ciphertext (encrypted, content_from_protobuf)

let box_to_protobuf content_to_protobuf box encoder =
  match box with
  | Ciphertext (encrypted, _) ->
    encrypted_to_protobuf encrypted encoder
  | Cleartext (content, secret_key, public_key)
      when secret_key.algorithm = public_key.algorithm ->
    let clear_bytes = Protobuf.Encoder.encode_bytes content_to_protobuf content in
    let encrypted   = encrypt clear_bytes secret_key public_key in
    encrypted_to_protobuf encrypted encoder
  | _ -> assert false

let store content secret_key public_key =
  Cleartext (content, secret_key, public_key)

let decrypt box secret_key public_key =
  match box with
  | Cleartext (content, secret_key', public_key') ->
    (* We already have the cleartext, but keys may not match. How to determine if
       they do with a public key system, where none of them are equal?
       Encrypt&decrypt a dummy string. *)
    decrypt (encrypt Bytes.empty secret_key' public_key') secret_key public_key |>
    Option.map (fun _ -> content)
  | Ciphertext (encrypted, content_from_protobuf) ->
    decrypt encrypted secret_key public_key |>
    Option.map (Protobuf.Decoder.decode_bytes content_from_protobuf)

