(*---------------------------------------------------------------------------
   Copyright (c) 2017 b0. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
   %%NAME%% %%VERSION%%
  ---------------------------------------------------------------------------*)

let ( >>= ) v f = match v with Ok v -> f v | Error _ as e -> e
let ( >>| ) v f = match v with Ok v -> Ok (f v) | Error _ as e -> e

module R = struct

  let reword_error reword = function
  | Ok _ as r -> r
  | Error e -> Error (reword e)

  let join r = match r with Ok v -> v | Error _ as e -> e

  type msg = [`Msg of string ]

  let msgf fmt =
    let kmsg _ = `Msg (Format.flush_str_formatter ()) in
    Format.kfprintf kmsg Format.str_formatter fmt

  let error_msg m = Error (`Msg m)
  let error_msgf fmt =
    let kerr _ = Error (`Msg (Format.flush_str_formatter ())) in
    Format.kfprintf kerr Format.str_formatter fmt

  let reword_error_msg ?(replace = false) reword = function
  | Ok _ as r -> r
  | Error (`Msg e) ->
      let (`Msg e' as v) = reword e in
      if replace then Error v else error_msgf "%s\n%s" e e'

  let open_error_msg = function Ok _ as r -> r | Error (`Msg _) as r -> r

  let failwith_error_msg = function Ok v -> v | Error (`Msg m) -> failwith m
end

type 'a result = ('a, [ `Msg of string ]) Pervasives.result

(*---------------------------------------------------------------------------
   Copyright (c) 2017 b0

   Permission to use, copy, modify, and/or distribute this software for any
   purpose with or without fee is hereby granted, provided that the above
   copyright notice and this permission notice appear in all copies.

   THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
   WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
   MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
   ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
   WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
   ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
   OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
  ---------------------------------------------------------------------------*)