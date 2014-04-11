(** Pathname manipulation.

    Derived from code by: db0 <db0company@gmail.com>,
    originally found at: https://github.com/db0company/Pathname *)

(** Type of pathnames. *)
type t

(** The directory separator ("/" on *nix, "\\" on Windows). *)
val sep : string

(** An empty path. *)
val empty : t

(** [is_empty p] returns [true] if [p] is an empty path. *)
val is_empty : t -> bool

(** [of_string s] creates a path from a string. *)
val of_string : string -> t

(** [of_list l] creates a path from a list. *)
val of_list : ?is_real:bool -> string list -> t

(** [concat a b] returns concatenation of [a] and [b]. *)
val concat : t -> t -> t

(** [extend p p'] appends path [p'] (represented as string) to path [p]. *)
val extend : t -> string -> t

(** [to_string p] converts path [p] to string. *)
val to_string : t -> string

(** [to_list p] returns list of components of [p]. *)
val to_list : t -> string list

(** [filename p] returns the last component of [p]. If [p]
    is empty, raises [Invalid_argument]. *)
val filename : t -> string

(** [basename p] returns all but the last component of [p]. If [p]
    is empty, raises [Invalid_argument]. *)
val basename : t -> t

(** [parent p] returns all but the last component of [p]. If [p]
    is empty, returns [p]. *)
val parent : t -> t

(** [extension p] returns the part of the last component of [p] after
    the last dot. *)
val extension : t -> string

(** [no_extension p] returns the part of the last component of [p] before
    the last dot. *)
val no_extension : t -> string
