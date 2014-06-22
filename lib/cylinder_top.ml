let () =
  Topdirs.dir_directory "./_build/lib";
  Topdirs.dir_directory "./_build/lib/core";
  Topdirs.dir_directory "./_build/lib/crypto";
  Topdirs.dir_directory "./_build/lib/backends";
  Topdirs.dir_directory "./_build/lib/config";
  Topdirs.dir_directory "./_build/lib/local";
  Topfind.load_deeply ["ZMQ"; "lwt"];
  UTop_main.main ()
