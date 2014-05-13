let () =
  Topdirs.dir_directory "./_build/lib";
  Topdirs.dir_directory "./_build/lib/core";
  Topdirs.dir_directory "./_build/lib/backends";
  Topfind.load_deeply ["lwt"];
  UTop_main.main ()
