(* ************************************************************************** *)
(* Project: PathName                                                          *)
(* Description: Module to manipulate filesystem paths                         *)
(* Author: db0 (db0company@gmail.com, http://db0.fr/)                         *)
(* Latest Version is on GitHub: https://github.com/db0company/Pathname        *)
(* ************************************************************************** *)

(* ************************************************************************** *)
(* Types                                                                      *)
(* ************************************************************************** *)

(* * True if real path, false if relative path                                *)
(* * List of each dir names in reverse order                                  *)
(* * The string representation of the path                                    *)
type t = (bool * string list * string)

(* ************************************************************************** *)
(* Values                                                                     *)
(* ************************************************************************** *)

(* sep : string                                                               *)
(* The directory separator (Example: "/" for Unix)                            *)
let sep = Filename.dir_sep

(* empty : t                                                                  *)
(* An empty path                                                              *)
let empty = (false, [], "")

(* ************************************************************************** *)
(* Constructors                                                               *)
(* ************************************************************************** *)

(* new_path : unit -> t                                                       *)
(* Return a new empty path                                                    *)
let make () = empty

(* string_of_list : bool -> string list -> string                             *)
(* Return a string of the list, taking into account if it is real or relative *)
let string_of_list r list =
  let str_ = String.concat sep list in
  if r then sep ^ str_ else str_

(* of_string : string -> t                                           *)
(* Return a new path initialized using a string                               *)
let of_string spath =
  let r = if (String.length spath) = 0 then false else spath.[0] = sep.[0]
  and list = (Str.split (Str.regexp sep) spath) in
  (r, (List.rev list), string_of_list r list)

(* of_list : ?is_real:bool -> string list -> t                       *)
(* Return a new path initialized using a list                                 *)
let of_list ?is_real:(r=false) list =
  (r, List.rev list, string_of_list r list)

(* ************************************************************************** *)
(* Operators                                                                  *)
(* ************************************************************************** *)

(* list_empty : 'a list -> bool                                               *)
(* Return true if the list is empty, false otherwise                          *)
let list_empty = function [] -> true | _  -> false

(* concat : t -> t -> t                                                       *)
(* Concatenate two paths and return the result                                *)
let concat (r, l1, s1) (_, l2, s2) =
  if list_empty l1
  then (r, l2, s2)
  else (r, (l2 @ l1), (s1 ^ sep ^ s2))

(* extend : t -> string -> t                                                  *)
(* Extend path dir, appends the directory to the path                         *)
let extend path extdir =
  concat path (of_string extdir)

(* extend' : t -> string -> t                                             *)
(* Extend path with a filename. Works only with raw filename, not paths.      *)
(* More efficient than extend.                                                *)
let extend' (r, l, s) filename =
  if list_empty l
  then (r, [filename], filename)
  else (r, (filename::l), (s ^ sep ^ filename))

(* ************************************************************************** *)
(* Get                                                                        *)
(* ************************************************************************** *)

(* to_string : t -> string                                                    *)
(* Return a string corresponding to the path                                  *)
let to_string (r, l, s) = s

(* to_list : t -> string list                                                 *)
(* Return a list of strings corresponding to the path                         *)
let to_list (_, l, s) = List.rev l

(* ************************************************************************** *)
(* Tools                                                                      *)
(* ************************************************************************** *)

(* filename : t -> string                                                     *)
(* Return the filename without the rest of the path                           *)
let filename (_, l, _) = List.hd l

let basename (r, l, s) = r, List.tl l, string_of_list r (List.rev (List.tl l))

(* parent : t -> t                                                            *)
(* Return the path without the last element                                   *)
(* Example: "foo/bar/baz" -> "foo/bar"                                        *)
let parent (r, l, _) =
  let new_list = match l with
    | h::t	-> t
    | []	-> [] in
  (r, new_list, string_of_list r (List.rev new_list))

(* extension : t -> string                                                    *)
(* Return the extansion of the given filename                                 *)
(* Example : "document.pdf" -> "pdf"                                          *)
let extension path =
  let f = filename path in
  let start = try (String.rindex f '.') + 1 with Not_found -> 0
  in try String.sub f start ((String.length f) - start)
    with Invalid_argument s -> ""

(* no_extension : t -> string                                                 *)
(* Return filename without its extension                                      *)
(* Example : "/foo/bar/document.pdf" -> "document"                            *)
let no_extension path =
  let f = filename path in
  let size =
    try (String.rindex f '.') with Not_found -> -1
  in try String.sub f 0 size with Invalid_argument s -> f

(* is_empty : t -> bool                                                       *)
(* Check if the path is empty                                                 *)
let is_empty (_, l, _) = list_empty l
