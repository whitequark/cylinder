let () =
  Topdirs.dir_directory "./_build/lib";
  Topdirs.dir_directory "./_build/lib/core";
  Topdirs.dir_directory "./_build/lib/crypto";
  Topdirs.dir_directory "./_build/lib/backends";
  Topfind.load_deeply ["ZMQ"; "lwt"];
  UTop_main.main ()
