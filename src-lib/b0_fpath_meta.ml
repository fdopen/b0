(*---------------------------------------------------------------------------
   Copyright (c) 2017 b0. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
   %%NAME%% %%VERSION%%
  ---------------------------------------------------------------------------*)

(* Metadata *)

module Key_info = struct
  type 'a t = unit
  let key_kind = "file metadata key"
  let key_namespaced = true
  let key_name_tty_color = `Default
  let pp _ = B0_fmt.nop
end

module Meta = B0_hmap.Make (Key_info) ()

module Meta_map = struct
  type t = Meta.t B0_fpath.map

  let empty = B0_fpath.Map.empty

  let mem p k m = match B0_fpath.Map.find p m with
  | meta -> Meta.mem k meta
  | exception Not_found -> false

  let add p k v m = match B0_fpath.Map.find p m with
  | meta -> B0_fpath.Map.add p (Meta.add k v meta) m
  | exception Not_found -> B0_fpath.Map.add p (Meta.add k v Meta.empty) m

  let rem p k m = match B0_fpath.Map.find p m with
  | meta -> B0_fpath.Map.add p (Meta.rem k meta) m
  | exception Not_found -> m

  let find p k m = match B0_fpath.Map.find p m with
  | meta -> Meta.find k meta
  | exception Not_found -> None

  let get p k m = match B0_fpath.Map.find p m with
  | meta -> Meta.get k meta
  | exception Not_found ->
      invalid_arg (B0_string.strf "%a is not bound in map" B0_fpath.pp p)

  let get_all p m = match B0_fpath.Map.find p m with
  | meta -> meta
  | exception Not_found -> Meta.empty
end

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