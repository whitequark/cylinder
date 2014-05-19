(* OASIS_START *)
(* OASIS_STOP *)

open Ocamlbuild_plugin;;

dispatch
  (MyOCamlbuildBase.dispatch_combine [
    begin function
    | After_rules ->
      let tag_atdgen env patterns =
        List.iter (fun p -> tag_file (env p) (Tags.elements (Tags.of_list ["package(atdgen)"]))) patterns
      in
      let atdgen = "atdgen" in
      rule "atdgen: .atd -> _t.ml*"
        ~prods:["%_t.ml";"%_t.mli"]
        ~dep:"%.atd"
        (begin fun env build ->
          tag_atdgen env ["%_t.ml";"%_t.mli"];
          Cmd (S [A atdgen; A "-t"; P (env "%.atd")]);
         end) ;
      rule "atdgen: .atd -> _j.ml*"
        ~prods:["%_j.ml";"%_j.mli";]
        ~dep:"%.atd"
        (begin fun env build ->
          tag_atdgen env ["%_j.ml"; "%_j.mli"];
          Cmd (S [A atdgen; A "-j"; A "-j-std"; P (env "%.atd")]);
         end) ;
    | _ -> ()
    end;
    dispatch_default
  ])
