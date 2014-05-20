type t = (Block.digest, bytes) Hashtbl.t

let create () = Hashtbl.create 16

let get store digest =
  try  Lwt.return (`Ok (Hashtbl.find store digest))
  with Not_found -> Lwt.return `Not_found

let exists store digest =
  try  ignore (Hashtbl.find store digest); Lwt.return `Ok
  with Not_found -> Lwt.return `Not_found

let put store digest obj =
  Hashtbl.replace store digest obj;
  Lwt.return `Ok

let erase store digest =
  Hashtbl.remove store digest;
  Lwt.return_unit

let enumerate store cookie =
  match cookie with
  | "(end)" -> Lwt.return `Exhausted
  | ""      -> if Hashtbl.length store <> 0
               then Lwt.return (`Ok ("(end)", Hashtbl.fold (fun d _ l -> d :: l) store []))
               else Lwt.return `Exhausted
  | _       -> assert false
