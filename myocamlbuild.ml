open Ocamlbuild_plugin;;

dispatch begin function
  | After_rules ->
    flag ["ocaml"; "compile"] (S[A"-w"; A"@5@8@10@11@12@14@23@24@26@29@40"]);
    flag ["ocaml"; "compile"; "debug"] (S[A"-ppopt"; A"-lwt-debug"]);
  | _ -> ()
end
