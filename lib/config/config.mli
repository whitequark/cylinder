(** Configuration file storage. *)

(** [locate ~app ~name] returns the appropriate path to a configuration file [name]
    of application [app] on the current platform.

    The location of configuration is platform-specific:
      * on Linux, [$(config_home)/.config/$(app)/$(name)], where [$(config_home)]
        is the first [:]-separated component of [$XDG_CONFIG_HOME], or [~/.config].
      * on other Unixes, [$HOME/.$(app)/$(name)]. *)
val locate : app:string -> name:string -> string

(** [load ~app ~name ~loader] attempts to load the configuration,
    deserializing it with [loader], and returns [Some cfg] if it is found,
    otherwise returns [None].
    @see locate *)
val load   : app:string -> name:string -> loader:(string -> 'a) -> 'a option

(** [store ~app ~name ~dumper cfg] stores configuration [cfg], serializing it
    with [dumper]. The configuration is written atomically. The file permissions
    are set so that only the current user will be able to read or modify it.
    @see locate *)
val store  : app:string -> name:string -> dumper:('a -> string) -> 'a -> unit

(** [init ~app ~name ~init ~loader ~dumper] attempts to load the configuration.
    If it is not found, the value returned by [init ()] is stored and returned.
    @see load *)
val init   : app:string -> name:string -> init:(unit -> 'a) ->
             loader:(string -> 'a) -> dumper:('a -> string) -> 'a
