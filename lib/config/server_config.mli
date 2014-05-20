type server_config = {
  secret_key : Box.secret_key;
  public_key : Box.public_key;
}

val server_config_of_string : string -> server_config
val server_config_to_string : server_config -> string
