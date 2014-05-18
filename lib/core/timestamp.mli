(** Timestamps. *)

(** Type of timestamps. Timestamps are represented by Unix
    time in milliseconds. *)
type t = private int64

(** Timestamp deltas. *)
module Delta : sig
  (** Type of timestamp deltas. Timestamp deltas are represented
      by differences in Unix times in milliseconds. *)
  type t = private int64

  (** [zero] is a delta corresponding to no difference in time. *)
  val zero : t

  (** [t_from_protobuf d] deserializes a timestamp delta from [d]. *)
  val t_from_protobuf  : Protobuf.Decoder.t -> t

  (** [t_to_protobuf t e] serializes timestamp delta [t] into [e]. *)
  val t_to_protobuf    : t -> Protobuf.Encoder.t -> unit

  (** [of_milliseconds dut] converts Unix time difference [dut] in
      milliseconds to a timestamp delta. *)
  val of_milliseconds : int64 -> t

  (** [to_milliseconds dt] converts a timestamp delta [dt] to Unix
      time difference in milliseconds. *)
  val to_milliseconds : t -> int64

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

(** [t_from_protobuf d] deserializes a timestamp from [d]. *)
val t_from_protobuf  : Protobuf.Decoder.t -> t

(** [t_to_protobuf t e] serializes timestamp [t] into [e]. *)
val t_to_protobuf    : t -> Protobuf.Encoder.t -> unit

(** [of_unix_time t] converts Unix time [t] (possibly returned
    by [Unix.time ()]) to a timestamp. *)
val of_unix_time : float -> t

(** [to_unix_time t] converts a timestamp [t] to Unix time. *)
val to_unix_time : t -> float

(** [of_milliseconds ut] converts Unix time [ut] in milliseconds to
    a timestamp. *)
val of_milliseconds : int64 -> t

(** [to_milliseconds t] converts a timestamp [t] to Unix time in
    milliseconds. *)
val to_milliseconds : t -> int64

(** [of_seconds ut] converts Unix time [ut] in seconds to
    a timestamp. *)
val of_seconds : int64 -> t

(** [to_seconds t] converts a timestamp [t] to Unix time in
    seconds. *)
val to_seconds : t -> int64

(** [to_string ?format t] converts a timestamp [t] to a formatted string. *)
val to_string : ?format:[`ISO8601|`HM|`MD] -> t -> string

(** [diff a b] returns a relative difference between [a] and [b]. *)
val diff : t -> t -> Delta.t

(** [advance t d] advances timestamp [t] by [d]. *)
val advance : t -> Delta.t -> t

(** [floor t p] rounds [t] down with [p] as unit. *)
val floor : t -> Delta.t -> t
