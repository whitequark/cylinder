(** Timestamps. *)

(** Type of timestamps. Timestamps are represented by Unix
    time in milliseconds. *)
type t = private int
with sexp

(** Timestamp deltas. *)
module Delta : sig
  (** Type of timestamp deltas. Timestamp deltas are represented
      by differences in Unix times in milliseconds. *)
  type t = private int
  with sexp

  (** [zero] is a delta corresponding to no difference in time. *)
  val zero : t

  (** [of_milliseconds dut] converts Unix time difference [dut] in
      milliseconds to a timestamp delta. *)
  val of_milliseconds : int -> t

  (** [to_milliseconds dt] converts a timestamp delta [dt] to Unix
      time difference in milliseconds. *)
  val to_milliseconds : t -> int

  (** [to_string dt] converts a timestamp delta [dt] to a formatted
      string. *)
  val to_string : t -> string

  (** [add a b] adds timestamp deltas [a] and [b]. *)
  val add : t -> t -> t

  (** [sub a b] subtracts timestamp delta [b] from [a]. *)
  val sub : t -> t -> t

  (** [div dt n] divides timestamp delta [dt] to [n] periods. *)
  val div : t -> int -> t
end

(** [zero] is a timestamp pointing to [1970-01-01 00:00 UTC]. *)
val zero : t

(** [now ()] returns a timestamp corresponding to current time. *)
val now : unit -> t

(** [of_unix_time t] converts Unix time [t] (possibly returned
    by [Unix.time ()]) to a timestamp. *)
val of_unix_time : float -> t

(** [to_unix_time t] converts a timestamp [t] to Unix time. *)
val to_unix_time : t -> float

(** [of_milliseconds ut] converts Unix time [ut] in milliseconds to
    a timestamp. *)
val of_milliseconds : int -> t

(** [to_milliseconds t] converts a timestamp [t] to Unix time in
    milliseconds. *)
val to_milliseconds : t -> int

(** [of_seconds ut] converts Unix time [ut] in seconds to
    a timestamp. *)
val of_seconds : int -> t

(** [to_seconds t] converts a timestamp [t] to Unix time in
    seconds. *)
val to_seconds : t -> int

(** [to_string ?format t] converts a timestamp [t] to a formatted string. *)
val to_string : ?format:[`ISO8601|`HM|`MD] -> t -> string

(** [diff a b] returns a relative difference between [a] and [b]. *)
val diff : t -> t -> Delta.t

(** [advance t d] advances timestamp [t] by [d]. *)
val advance : t -> Delta.t -> t

(** [floor t p] rounds [t] down with [p] as unit. *)
val floor : t -> Delta.t -> t
