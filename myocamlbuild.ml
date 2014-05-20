(* OASIS_START *)
(* OASIS_STOP *)

open Ocamlbuild_plugin;;

dispatch
  (MyOCamlbuildBase.dispatch_combine [
    begin function
    | After_rules ->
      (* No findlib support yet *)
      flag ["ocaml"; "ocamldep"; "pkg_lwt"] (S[A"-ppx"; A"ppx_lwt"])
    | _ -> ()
    end;
    dispatch_default
  ])
;;
