(** File content storage. *)

module Capability : sig
  (** A capability [uuid, key] is necessary and sufficient to retrieve a block
      from a blockserver. *)
  type t = (Uuidm.t * Key.t)
end

(** A block is an encrypted unit of storage of a blockserver. *)
type t = private (Uuidm.t * Lwt_bytes.t)

(** [encrypt ~convergence data] encrypts [data] with convergence key
    [convergence]. *)
val encrypt : convergence:string -> Lwt_bytes.t -> (Sodium.Secret_box.secret_key * t)

(** [decrypt (key, block)] decrypts [block] using [key]. *)
val decrypt : (Sodium.Secret_box.secret_key * t) -> Lwt_bytes.t
