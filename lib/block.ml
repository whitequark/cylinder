module Key = struct
  type t
end

module Capability = struct
  type t = (Uuidm.t * Key.t)
end

type t = (Uuidm.t * Lwt_bytes.t)

let encrypt ~convergence cleartext =
  assert false

let decrypt (key, block) =
  assert false
