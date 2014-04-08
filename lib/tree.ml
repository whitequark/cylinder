open Sexplib.Std
open ExtList
open Lwt

type entry = {
  mutable parent    : entry option;
  mutable name      : string;
  mutable modified  : modified;
          content   : content;
}
and modified = Uuidm.t * Timestamp.t
and content =
| Directory of directory
| File
and directory = {
  mutable children  : entry list;
}

let author entry = fst entry.modified
let timestamp entry = snd entry.modified

let rec path_of_entry entry =
  match entry.parent with
  | Some parent -> Pathname.extend (path_of_entry parent) entry.name
  | None        -> Pathname.of_list [entry.name]

let find entry name =
  match entry.content with
  | File -> invalid_arg "Tree.find: file passed"
  | Directory { children } ->
    List.find (fun child -> child.name = name) children

let find_option entry name =
  try  Some (find entry name)
  with Not_found -> None

let append entry child =
  match entry.content with
  | File -> invalid_arg "Tree.create: file passed"
  | Directory dir ->
    assert ((find_option entry child.name) = None);
    dir.children <- dir.children @ [child];
    child.parent <- Some entry

let create entry name modified content =
  let child = { parent = None; name; modified; content; } in
  append entry child;
  child

let delete entry =
  entry.parent |> Option.may (fun parent ->
    match parent.content with
    | Directory dir ->
      assert (List.memq entry dir.children);
      dir.children <- List.remove_if ((==) entry) dir.children;
      entry.parent <- None
    | File -> assert false)

let string_of_entry entry =
  let rec string_of_entry' ~level entry =
    let current =
      Printf.sprintf "%s| %S (%s at %s)\n"
                     (String.make (level * 2) ' ')
                     entry.name
                     (Uuidm.to_string (author entry))
                     (Timestamp.to_string (timestamp entry))
    in
    match entry.content with
    | File -> current
    | Directory { children } ->
      let children' =
        children |>
        List.map (fun child -> string_of_entry' ~level:(level + 1) child) |>
        String.concat ""
      in
      current ^ children'
  in
  string_of_entry' ~level:0 entry

let watch ~author path =
  let selector = Inotify.([S_Attrib; S_Create; S_Modify; S_Delete; S_Move;
                           S_Dont_follow; S_Onlydir]) in
  lwt inotify  = Lwt_inotify.create () in
  let watches  = Hashtbl.create 10 in
  let rec entry_of_path parent path =
    let name     = Pathname.filename path in
    try_lwt
      lwt stat     = Lwt_unix.lstat (Pathname.to_string path) in
      let modified = author, Timestamp.of_unix_time stat.Lwt_unix.st_ctime in
      match stat.Lwt_unix.st_kind with
      | Lwt_unix.S_REG | Lwt_unix.S_LNK ->
        return (Some { parent; name; modified; content = File })
      | Lwt_unix.S_DIR ->
        (* Create entry for this directory. *)
        let directory = { children = [] } in
        let entry     = { parent; name; modified; content = Directory directory; } in
        (* Set up inotify *before* traversing; this way anything that
           is added while traversing is not lost. *)
        let selector = if parent = None then selector @ [Inotify.S_Move_self] else selector in
        lwt watch = Lwt_inotify.add_watch inotify (Pathname.to_string path) selector in
        Hashtbl.add watches watch entry;
        (* Traverse the directory. *)
        lwt children = children_of_path entry path in
        directory.children <- children;
        return (Some entry)
      | Lwt_unix.S_CHR  | Lwt_unix.S_BLK
      | Lwt_unix.S_FIFO | Lwt_unix.S_SOCK ->
        return_none
    with Unix.Unix_error (Unix.ENOENT, "lstat", _) ->
      (* The file was deleted before we could traverse it. *)
      return_none
  and children_of_path parent path =
    Lwt_unix.files_of_directory (Pathname.to_string path) |>
    Lwt_stream.filter_map_s (fun fn ->
      if fn = "." || fn = ".." then return_none
      else entry_of_path (Some parent) (Pathname.extend path fn)) |>
    Lwt_stream.to_list
  in
  lwt root =
    match_lwt entry_of_path None path with
    | Some entry -> return entry
    | None -> raise_lwt (Failure "root is not a file or directory")
  in
  let cookies = ref [] in
  let rec listen () =
    lwt (watch, events, cookie, name) = Lwt_inotify.read inotify in
    prerr_endline (Inotify.string_of_event (watch, events, cookie, name));
    (* Check for queue overflow. Q_overflow arrives with watch=-1, so that
       would crash on Hashtbl.find. *)
    begin match events with
    | [Inotify.Q_overflow] -> raise_lwt (Failure "Tree.watch: queue overflow")
    | _ -> return_nil
    end >>
    (* In general, filesystem events arrive strictly in order, but may
       arbitrarily race against initial traversal of filesystem. It is guaranteed
       that no events will be missed, but at any moment, an event may arrive
       whose action has already been applied to the tree.

       Hence, if an inconsistency with the shadow tree is detected, we generally
       assume that the state of the tree is younger than the event. *)
    let entry = Hashtbl.find watches watch in
    begin match events with
    (* File was created *)
    | [Inotify.Create] ->
      let name = Option.get name in
      if (find_option entry name) = None then
        ignore (create entry name (author, Timestamp.now ()) File);
      return_unit
    (* Directory was created *)
    | [Inotify.Isdir; Inotify.Create] ->
      let name = Option.get name in
      if (find_option entry name) = None then begin
        try_lwt
          (* Create new directory in the tree. *)
          let directory = { children = [] } in
          let entry' = create entry name (author, Timestamp.now ()) (Directory directory) in
          let path'  = path_of_entry entry' in
          (* Add inotify watcher. *)
          lwt watch  = Lwt_inotify.add_watch inotify (Pathname.to_string path') selector in
          Hashtbl.add watches watch entry';
          (* Populate it with (possibly already existing) children. *)
          lwt children = children_of_path entry' path' in
          directory.children <- children;
          return_unit
        with Unix.Unix_error(Unix.ENOENT, ("inotify_add_watch" | "opendir"), _) ->
          (* The directory was deleted before we received the event, or,
             the directory was deleted before we could traverse i. t*)
          return_unit
      end else
        return_unit
    (* File or directory was deleted *)
    | [Inotify.Delete] | [Inotify.Isdir; Inotify.Delete] ->
      begin try_lwt
        delete (find entry (Option.get name));
        return_unit
      with Not_found ->
        return_unit
      end
    (* File or directory was moved *)
    | [Inotify.Moved_from] | [Inotify.Isdir; Inotify.Moved_from] ->
      begin try_lwt
        let entry' = find entry (Option.get name) in
        cookies := (cookie, entry') :: !cookies;
        delete entry';
        return_unit
      with Not_found ->
        return_unit
      end
    | [Inotify.Moved_to] | [Inotify.Isdir; Inotify.Moved_to] ->
      begin try_lwt
        let entry' = List.assoc cookie !cookies in
        cookies := List.remove_assoc cookie !cookies;
        let name'  = Option.get name in
        Option.may delete (find_option entry name');
        entry'.name <- name';
        append entry entry';
        return_unit
      with Not_found ->
        return_unit
      end
    (* Attributes of file or directory were changed, or file was modified *)
    | [Inotify.Attrib] | [Inotify.Isdir; Inotify.Attrib] | [Inotify.Modify] ->
      begin try_lwt
        let entry = Option.map_default (find entry) entry name in
        lwt stat  = Lwt_unix.lstat (Pathname.to_string (path_of_entry entry)) in
        let (author, timestamp) = entry.modified in
        entry.modified <- (author, Timestamp.of_unix_time stat.Lwt_unix.st_mtime);
        return_unit
      with Not_found | Unix.Unix_error (Unix.ENOENT, "lstat", _) ->
        (* The file was deleted before we received the event, or,
           the file was deleted before we could invoke lstat. *)
        return_unit
      end
    (* Deleted file or directory is no longer watched *)
    | [Inotify.Ignored] -> Hashtbl.remove watches watch; return_unit
    (* The root was moved (only root has S_Move_self) *)
    | [Inotify.Move_self] -> raise_lwt (Failure "Tree.watch: root was moved")
    (* Something we didn't expect *)
    | _ -> raise_lwt (Failure (Printf.sprintf "Tree.watch: unknown event %s"
                               (String.concat ", " (List.map Inotify.string_of_event_kind events))))
    end >>= fun () ->
    print_endline (string_of_entry root);
    listen ()
  in
  listen ()
