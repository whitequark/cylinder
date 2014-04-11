(* Derived from code by: db0 <db0company@gmail.com>,
   originally found at: https://github.com/db0company/Pathname *)

(** Type of pathnames: [real, lst, str]. [real] indicates whether the path
    is absolute. [lst] contains path components in reverse order. [str]
    contains string representation of path. *)
type t = (bool * string list * string)

let sep =
  Filename.dir_sep

let empty =
  (false, [], "")

let string_of_list r lst =
  let str = String.concat sep lst in
  if r then sep ^ str else str

let of_string str =
  let r = if (String.length str) = 0 then false else str.[0] = sep.[0] in
  let lst =
    let rec split pos rest =
      try
        let index = String.index_from str pos sep.[0] in
        split (index + 1) ((String.sub str pos (index - pos)) :: rest)
      with Not_found ->
        String.sub str pos ((String.length str) - pos) :: rest
    in
    split 0 []
  in
  (r, lst, string_of_list r lst)

let of_list ?is_real:(r=false) lst =
  (r, List.rev lst, string_of_list r lst)

let concat (r, l1, s1) (_, l2, s2) =
  if l1 = []
  then (r, l2, s2)
  else (r, (l2 @ l1), (s1 ^ sep ^ s2))

let extend path extdir =
  concat path (of_string extdir)

let to_string (r, l, s) =
  s

let to_list (_, l, s) =
  List.rev l

let filename (_, l, _) =
  if l = [] then invalid_arg "Pathname.filename";
  List.hd l

let basename (r, l, s) =
  if l = [] then invalid_arg "Pathname.basename";
  r, List.tl l, string_of_list r (List.rev (List.tl l))

let parent (r, l, _) =
  let new_list =
    match l with
    | h::t -> t
    | []	 -> []
  in
  (r, new_list, string_of_list r (List.rev new_list))

let extension path =
  let f = filename path in
  try
    let start = (String.rindex f '.') + 1 in
    String.sub f start ((String.length f) - start)
  with Not_found ->
    ""

let no_extension path =
  let f = filename path in
  try
    String.sub f 0 (String.rindex f '.')
  with Not_found ->
    f

let is_empty (_, l, _) =
  l = []
