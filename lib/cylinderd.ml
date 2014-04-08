open Lwt

let _ =
  Lwt_main.run (
    let me   = Uuidm.create `V4 in
    lwt root = Tree.watch me (Pathname.of_string Sys.argv.(1)) in
    print_endline (Tree.string_of_entry root);
    return ())
