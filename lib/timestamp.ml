open Sexplib.Std

type t = int
with sexp

module Delta = struct
  type t = int
  with sexp

  let zero = 0

  let of_milliseconds dut = dut
  let to_milliseconds dt  = dt

  let to_string dt =
    Printf.sprintf "%+dms" dt

  let add a b = a + b
  let sub a b = a - b
  let div dt n = dt / n
end

let zero = 0

let of_unix_time time =
  int_of_float (time *. 1000.)

let to_unix_time timestamp =
  (float_of_int timestamp) /. 1000.

let of_milliseconds time = time
let to_milliseconds timestamp = timestamp

let of_seconds time = time * 1000
let to_seconds timestamp = timestamp / 1000

let to_string ?(format=`ISO8601) timestamp =
  let open Unix in
  let gmt = gmtime (to_unix_time timestamp) in
  match format with
  | `ISO8601 ->
    Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ"
      (1900 + gmt.tm_year) (1 + gmt.tm_mon) gmt.tm_mday
      gmt.tm_hour gmt.tm_min gmt.tm_sec (timestamp mod 1000)
  | `HM -> Printf.sprintf "%02d:%02d" gmt.tm_hour gmt.tm_min
  | `MD -> Printf.sprintf "%02d-%02d" (1 + gmt.tm_mon) gmt.tm_mday

let now () =
  of_unix_time (Unix.gettimeofday ())

let diff a b = b - a
let advance t n = t + n
let floor t p = t - t mod p
