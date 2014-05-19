(** Configuration file storage. *)

(** [locate ~app ~name] returns the appropriate path to a configuration file [name]
    of application [app] on the current platform.

    The location of configuration is platform-specific:
      * on Linux, [$(config_home)/.config/$(app)/$(name)], where [$(config_home)]
        is the first [:]-separated component of [$XDG_CONFIG_HOME], or [~/.config].
      * on other Unixes, [$HOME/.$(app)/$(name)]. *)
val locate : app:string -> name:string -> string

(** [load ~app ~name ~init f] attempts to load the configuration,
    deserializing it with [f], and returns [Some cfg] if it is found.

    If the configuration is not found, returns [Some (init ())] if
    [init] is passed, or [None].
    @see locate *)
val load   : app:string -> name:string -> ?init:(unit -> 'a) -> (string -> 'a) -> 'a option

(** [store ~app ~name f cfg] stores configuration [cfg], serializing it
    with [f]. The configuration is written atomically. The file permissions
    are set so that only the current user will be able to read or modify it.
    @see locate *)
val store  : app:string -> name:string -> ('a -> string) -> 'a -> unit
