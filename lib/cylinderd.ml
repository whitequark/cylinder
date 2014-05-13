open Lwt

let _ =
  Lwt_main.run (
    let%lwt root = Tree.watch (Pathname.of_string Sys.argv.(1)) in
    print_endline (Tree.string_of_entry root);
    return ())
