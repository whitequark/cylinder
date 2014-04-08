(* ************************************************************************** *)
(* Project: PathName                                                          *)
(* Description: Module to manipulate filesystem paths                         *)
(* Author: db0 (db0company@gmail.com, http://db0.fr/)                         *)
(* Latest Version is on GitHub: https://github.com/db0company/Pathname        *)
(* ************************************************************************** *)

(* ************************************************************************** *)
(* Types                                                                      *)
(* ************************************************************************** *)

type t

(* ************************************************************************** *)
(* Values                                                                     *)
(* ************************************************************************** *)

(* The directory separator (Example: "/" for Unix)                            *)
val sep : string

(* An empty path                                                              *)
val empty : t

(* ************************************************************************** *)
(* Constructors                                                               *)
(* ************************************************************************** *)

(* Return a new empty path                                                    *)
val make : unit -> t

(* Return a new path initialized using a string                               *)
val of_string : string -> t

(* Return a new path initialized using a list                                 *)
val of_list : ?is_real:bool -> string list -> t

(* ************************************************************************** *)
(* Operators                                                                  *)
(* ************************************************************************** *)

(* Concatenate two paths and return the result                                *)
val concat : t -> t -> t

(* Extend path dir, appends the directory to the path                         *)
val extend : t -> string -> t

(* Extend path with a filename. Works only with raw filename, not paths.      *)
(* More efficient than extend.                                                *)
val extend' : t -> string -> t

(* ************************************************************************** *)
(* Get                                                                        *)
(* ************************************************************************** *)

(* Return a string corresponding to the path                                  *)
val to_string : t -> string

(* Return a list of strings corresponding to the path                         *)
val to_list : t -> string list

(* ************************************************************************** *)
(* Tools                                                                      *)
(* ************************************************************************** *)

(* Return the filename without the rest of the path                           *)
val filename : t -> string

val basename : t -> t

(* Return the path without the last element                                   *)
(* Example: "foo/bar/baz" -> "foo/bar"                                        *)
val parent : t -> t

(* Return the extansion of the given filename                                 *)
(* Example: "document.pdf" -> "pdf"                                           *)
val extension : t -> string

(* Return filename without its extension                                      *)
(* Example: "/foo/bar/document.pdf" -> "document"                             *)
val no_extension : t -> string

(* Check if the path is empty                                                 *)
val is_empty : t -> bool
