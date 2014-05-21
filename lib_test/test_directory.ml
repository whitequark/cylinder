open OUnit2

let (>>=) = Lwt.(>>=)
let run f ctxt = Lwt_main.run (f ctxt)

let test_shadow ctxt =
  assert false

let suite = "Test Directory" >::: [
    (* "test_shadow" >:: run test_shadow; *)
  ]
