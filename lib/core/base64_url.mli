(** URL-safe base-64 encoding.

    This encoding is similar to regular Base64, but it uses [-_]
    instead of [+/], and does not have padding at the end. *)

(** [encode b] encodes [b] using RFC 4648 'base64url' encoding. *)
val encode : bytes -> bytes

(** [decode b] decodes [b] using RFC 4648 'base64url' and returns
    [Some b'] or [None] if [b] contains invalid characters. *)
val decode : bytes -> bytes option
