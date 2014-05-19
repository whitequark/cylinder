let locate ~app ~name =
  if Sys.unix then
    let home = Sys.getenv "HOME" in
    match ExtUnix.All.uname () with
    | { ExtUnix.All.Uname.sysname = "Linux" } ->
      let xdg_config_home =
        try  List.hd (ExtString.String.nsplit (Sys.getenv "XDG_CONFIG_HOME") ":")
        with Not_found | Failure "hd" -> Filename.concat home ".config"
      in
      List.fold_left Filename.concat xdg_config_home [app; name]
    | _ -> (* duplication courtesy PR6432 *)
      List.fold_left Filename.concat home ["." ^ app; name]
    | exception (ExtUnix.All.Not_available _) ->
      List.fold_left Filename.concat home ["." ^ app; name]
  else
    assert false

let load ~app ~name ?init f =
  let file = locate ~app ~name in
  try
    let fd  = Unix.openfile file [Unix.O_RDONLY] 0 in
    let buf = Buffer.create 16 in
    let rec read () =
      let buf' = Bytes.create 1024 in
      match Unix.read fd buf' 0 (Bytes.length buf') with
      | 0 -> Buffer.contents buf
      | n -> Buffer.add_subbytes buf buf' 0 n; read ()
    in
    Some (f (read ()))
  with Unix.Unix_error(Unix.ENOENT, _, _) ->
    match init with
    | Some f -> Some (f ())
    | None -> None

let store ~app ~name f cfg =
  let file = locate ~app ~name in
  FileUtil.mkdir ~parent:true (FilePath.dirname file);
  let temp = file ^ ".new" in
  try Unix.unlink temp with Unix.Unix_error (Unix.ENOENT, _, _) -> ();
  let fd   = Unix.openfile temp [Unix.O_WRONLY; Unix.O_CREAT] 0o600 in
  let buf  = f cfg in
  let rec write pos =
    match Unix.write fd buf pos ((Bytes.length buf) - pos) with
    | 0 -> ()
    | n -> write (pos + n)
  in
  write 0;
  Unix.close fd;
  Unix.rename temp file
