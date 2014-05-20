open OUnit2

let (>>=) = Lwt.(>>=)
let run f ctxt = Lwt_main.run (f ctxt)

module Test_backend(Backend: sig
  include Block.BACKEND
  val create : unit -> t Lwt.t
end) = struct
  let test_store_retrieve ctxt =
    let digest = Block.digest_bytes (Bytes.of_string "the quick brown fox") in
    let%lwt store  = Backend.create () in
    let%lwt result = Backend.get store digest in
    assert_equal `Not_found result;
    let%lwt result = Backend.exists store digest in
    assert_equal `Not_found result;
    let%lwt result = Backend.put store digest "the quick brown fox" in
    assert_equal `Ok result;
    let%lwt result = Backend.get store digest in
    assert_equal (`Ok "the quick brown fox") result;
    let%lwt result = Backend.exists store digest in
    assert_equal `Ok result;
    Lwt.return_unit

  let test_erase ctxt =
    let digest = Block.digest_bytes (Bytes.of_string "the quick brown fox") in
    let%lwt store  = Backend.create () in
    let%lwt result = Backend.put store digest "the quick brown fox" in
    assert_equal `Ok result;
    Backend.erase store digest >>= fun () ->
    let%lwt result = Backend.get store digest in
    assert_equal `Not_found result;
    Lwt.return_unit

  let test_enumerate ctxt =
    let digest1 = Block.digest_bytes (Bytes.of_string "the quick brown fox") in
    let digest2 = Block.digest_bytes (Bytes.of_string "the quick red fox") in
    let%lwt store  = Backend.create () in
    let%lwt result = Backend.enumerate store "" in
    assert_equal `Exhausted result;
    let%lwt result = Backend.put store digest1 "the quick brown fox" in
    assert_equal `Ok result;
    let%lwt result = Backend.put store digest2 "the quick red fox" in
    assert_equal `Ok result;
    match%lwt Backend.enumerate store "" with
    | `Ok (cookie, lst) ->
      assert_equal (ExtList.List.sort  lst) (ExtList.List.sort [digest1; digest2]);
      Lwt.return_unit
    | _ -> assert_failure "Backend.enumerate"

  let suite = [
      "test_store_retrieve" >:: run test_store_retrieve;
      "test_erase"          >:: run test_erase;
      "test_enumerate"      >:: run test_enumerate;
    ]
end

let suite = "Test backends" >::: [
    "Test In_memory_store" >:::
      (let module M = Test_backend(struct
         include In_memory_store
         let create () = Lwt.return (In_memory_store.create ())
       end) in M.suite);
  ]
