open OUnit2

let printer   = Printf.sprintf "%S"
let home      = Sys.getenv "HOME"
let app, name = "foo", "bar.json"

let test_locate_unix ctxt =
  if Sys.unix && ExtUnix.All.((uname ()).Uname.sysname <> "Linux") then
    assert_equal ~printer (Filename.concat home ".foo/bar.json")
                          (Config.locate ~app ~name)

let test_locate_linux ctxt =
  if Sys.unix && ExtUnix.All.((uname ()).Uname.sysname = "Linux") then
    assert_equal ~printer (Filename.concat home ".config/foo/bar.json")
                          (Config.locate ~app ~name)

let test_locate_linux_xdg ctxt =
  let dir = bracket_tmpdir ~prefix:"camlhome" ctxt in
  if Sys.unix && ExtUnix.All.((uname ()).Uname.sysname = "Linux") then
    Helper.with_env "XDG_CONFIG_HOME" dir (fun () ->
    assert_equal ~printer (Filename.concat dir "foo/bar.json")
                          (Config.locate ~app ~name))

let test_locate_linux_xdg_multi ctxt =
  let dir = bracket_tmpdir ~prefix:"camlhome" ctxt in
  if Sys.unix && ExtUnix.All.((uname ()).Uname.sysname = "Linux") then
    Helper.with_env "XDG_CONFIG_HOME" (dir ^ ":/foo/bar") (fun () ->
    assert_equal ~printer (Filename.concat dir "foo/bar.json")
                          (Config.locate ~app ~name))

let test_init ctxt =
  assert_equal ~printer "foo" (Config.init ~app ~name ~init:(fun () -> "foo")
                                           ~loader:String.lowercase ~dumper:String.uppercase);
  assert_equal ~printer "foo" (Config.init ~app ~name ~init:(fun () -> assert false)
                                           ~loader:String.lowercase ~dumper:String.uppercase);
  FileUtil.rm ~recurse:true [Config.locate ~app ~name:""]

let printer x = Option.default "" x

let test_load_empty ctxt =
  assert_equal ~printer None (Config.load ~app ~name ~loader:(fun x -> x))

let test_roundtrip ctxt =
  Config.store ~app ~name ~dumper:String.uppercase "foo";
  assert_equal ~printer (Some "foo") (Config.load ~app ~name ~loader:String.lowercase);
  Config.store ~app ~name ~dumper:String.uppercase "bar";
  assert_equal ~printer (Some "bar") (Config.load ~app ~name ~loader:String.lowercase);
  assert_equal 0o600 (Unix.stat (Config.locate ~app ~name)).Unix.st_perm;
  FileUtil.rm ~recurse:true [Config.locate ~app ~name:""]

let suite = "Test Config" >::: [
    "test_locate_unix"            >:: test_locate_unix;
    "test_locate_linux"           >:: test_locate_linux;
    "test_locate_linux_xdg"       >:: test_locate_linux_xdg;
    "test_locate_linux_xdg_multi" >:: test_locate_linux_xdg_multi;
    "test_load_empty"             >:: test_load_empty;
    "test_roundtrip"              >:: test_roundtrip;
  ]
