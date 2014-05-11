type t
val create    : unit -> t
val get       : t -> Block.digest -> [> `Ok of string | `Not_found ] Lwt.t
val put       : t -> Block.digest -> string -> [> `Ok ] Lwt.t
val erase     : t -> Block.digest -> unit Lwt.t
val enumerate : t -> string -> [ `Ok of (string * Block.digest list) | `Exhausted ] Lwt.t
