(*---------------------------------------------------------------------------
   Copyright (c) 2018 The b0 programmers. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
  ---------------------------------------------------------------------------*)

open B00_std
open B000

module Env = struct
  type tool_lookup = Cmd.tool -> (Fpath.t, string) result

  let env_tool_lookup ?sep ?(var = "PATH") env =
    let search_path = match String.Map.find var env with
    | exception Not_found -> "" | s -> s
    in
    match Fpath.list_of_search_path ?sep search_path with
    | Error _ as e -> fun _ -> e
    | Ok search -> fun tool -> Os.Cmd.must_find_tool ~search tool

  type t =
    { env : Os.Env.t;
      forced_env : Os.Env.t;
      lookup : tool_lookup }

  let memo lookup =
    let memo = Hashtbl.create 91 in
    fun tool -> match Hashtbl.find memo tool with
    | exception Not_found -> let p = lookup tool in Hashtbl.add memo tool p; p
    | p -> p

  let v ?lookup ?(forced_env = String.Map.empty) env =
    let lookup = match lookup with None -> env_tool_lookup env | Some l -> l in
    let lookup = memo lookup in
    { env; forced_env; lookup }

  let env e = e.env
  let forced_env e = e.forced_env
  let tool e l = e.lookup l
end

module Tool = struct
  type env_vars = string list
  let tmp_vars = ["TMPDIR"; "TEMP"; "TMP"]

  type response_file =
    { to_file : Cmd.t -> string;
      cli : Fpath.t -> Cmd.t; }

  let response_file_of to_file cli = { to_file; cli }
  let args0 =
    let to_file cmd = String.concat "\x00" (Cmd.to_list cmd) ^ "\x00" in
    let cli f = Cmd.(arg "-args0" %% path f) in
    { to_file; cli }

  type t =
    { name : Fpath.t;
      vars : env_vars;
      unstamped_vars : env_vars;
      response_file : response_file option; }

  let v ?response_file ?(unstamped_vars = tmp_vars) ?(vars = []) name =
    { name; vars; unstamped_vars; response_file }

  let by_name ?response_file ?unstamped_vars ?vars name =
    match Fpath.is_seg name with
    | false -> Fmt.invalid_arg "%S: tool is not a path segment" name
    | true -> v ?unstamped_vars ?vars (Fpath.v name)

  let name t = t.name
  let vars t = t.vars
  let unstamped_vars t = t.unstamped_vars
  let response_file t = t.response_file
  let read_env t env =
    let add_var acc var = match String.Map.find var env with
    | v -> String.Map.add var v acc
    | exception Not_found -> acc
    in
    let stamped = List.fold_left add_var String.Map.empty t.vars in
    let all = List.fold_left add_var stamped t.unstamped_vars in
    all, stamped
end

module Memo = struct
  type feedback =
  [ `Miss_tool of Tool.t * string
  | `Op_complete of Op.t ]

  type t = { c : ctx; m : memo }
  and ctx = { mark : Op.mark }
  and memo =
    { clock : Time.counter;
      cpu_clock : Time.cpu_counter;
      feedback : feedback -> unit;
      cwd : Fpath.t;
      env : Env.t ;
      guard : Guard.t;
      reviver : Reviver.t;
      exec : Exec.t;
      fiber_ready : (unit -> unit) Rqueue.t;
      mutable has_failures : bool;
      mutable op_id : int;
      mutable ops : Op.t list;
      mutable ready_roots : Fpath.Set.t; }

  let create ?clock ?cpu_clock:cc ~feedback ~cwd env guard reviver exec =
    let clock = match clock with None -> Time.counter () | Some c -> c in
    let cpu_clock = match cc with None -> Time.cpu_counter () | Some c -> c in
    let fiber_ready = Rqueue.empty () and op_id = 0 and  ops = [] in
    let c = { mark = "" } in
    let m =
      { clock; cpu_clock; feedback; cwd; env; guard; reviver; exec; fiber_ready;
        has_failures = false; op_id; ops; ready_roots = Fpath.Set.empty }
    in
    { c; m }

  let memo
      ?(hash_fun = (module Hash.Xxh_64 : Hash.T)) ?env ?cwd ?cache_dir
      ?trash_dir ?(jobs = B00_std.Os.Cpu.logical_count ()) ?feedback ()
    =
    let feedback = match feedback with | Some f -> f | None -> fun _ -> () in
    let fb_exec = (feedback :> Exec.feedback -> unit) in
    let fb_memo = (feedback :> feedback -> unit) in
    let clock = Time.counter () in
    let env = match env with None -> Os.Env.current () | Some env -> Ok env in
    let cwd = match cwd with None -> Os.Dir.cwd () | Some cwd -> Ok cwd in
    Result.bind env @@ fun env ->
    Result.bind cwd @@ fun cwd ->
    (* FIXME remove these defaults. *)
    let cache_dir = match cache_dir with
    | None -> Fpath.(cwd / "_b0" / ".cache") | Some d -> d
    in
    let trash_dir = match trash_dir with
    | None -> Fpath.(cwd / "_b0" / ".trash") | Some d -> d
    in
    Result.bind (File_cache.create cache_dir) @@ fun cache ->
    let env = Env.v env in
    let guard = Guard.create () in
    let reviver = Reviver.create clock hash_fun cache in
    let trash = Trash.create trash_dir in
    let exec = Exec.create ~clock ~feedback:fb_exec ~trash ~jobs () in
    Ok (create ~clock ~feedback:fb_memo ~cwd env guard reviver exec)

  let clock m = m.m.clock
  let cpu_clock m = m.m.cpu_clock
  let env m = m.m.env
  let reviver m = m.m.reviver
  let guard m = m.m.guard
  let exec m = m.m.exec
  let trash m = Exec.trash m.m.exec
  let delete_trash ~block m = Trash.delete ~block (trash m)
  let hash_string m s = Reviver.hash_string m.m.reviver s
  let hash_file m f = Reviver.hash_file m.m.reviver f
  let ops m = m.m.ops
  let timestamp m = Time.count m.m.clock
  let new_op_id m = let id = m.m.op_id in m.m.op_id <- id + 1; id
  let mark m = m.c.mark
  let with_mark m mark = { c = { mark }; m = m.m }
  let has_failures m = m.m.has_failures
  let add_op m o = m.m.ops <- o :: m.m.ops; Guard.add m.m.guard o

  (* Fibers *)

  type 'a fiber = ('a -> unit) -> unit
  exception Fail

  let notify_op m ?k kind msg =
    let k = match k with None -> None | Some k -> Some (fun o -> k ()) in
    let id = new_op_id m and created = timestamp m in
    let o = Op.Notify.v_op ~id ~mark:m.c.mark ~created ?k kind msg in
    add_op m o

  let notify_reviver_error m kind o e =
    notify_op m kind (Fmt.str "@[cache error: op %d: %s@]" (Op.id o) e)

  let fail m fmt =
    let k msg = notify_op m `Fail msg; raise Fail in
    Fmt.kstr k fmt

  let fail_if_error m = function Ok v -> v | Error e -> fail m "%s" e

  let invoke_k m ~pp_kind k v = try k v with
  | Stack_overflow as e -> raise e
  | Out_of_memory as e -> raise e
  | Sys.Break as e -> raise e
  | Fail -> ()
  | e ->
      let bt = Printexc.get_raw_backtrace () in
      let err =
        Fmt.str "@[<v>%a raised unexpectedly:@,%a@]"
          pp_kind v Fmt.exn_backtrace (e, bt)
      in
      notify_op m `Fail err

  let spawn_fiber m k = Rqueue.add m.m.fiber_ready (fun () -> k ())
  let continue_fiber m k =
    let pp_kind ppf () = Fmt.string ppf "Fiber" in
    invoke_k m ~pp_kind k ()

  let continue_op m o =
    let pp_kind ppf o = Fmt.pf ppf "Continuation of operation %d" (Op.id o) in
    List.iter (Guard.set_file_ready m.m.guard) (Op.writes o);
    m.m.feedback (`Op_complete o);
    invoke_k m ~pp_kind Op.invoke_k o

  let discontinue_op m o =
    (* This is may not be entirely clear from the code :-( but any failed op
       or fiber means this function eventually gets called, hereby giving
       [has_failure] its appropriate semantics. *)
    m.m.has_failures <- true;
    List.iter (Guard.set_file_never m.m.guard) (Op.writes o);
    Op.discard_k o; m.m.feedback (`Op_complete o)

  let finish_op m o = match Op.status o with
  | Op.Done ->
      if Op.revived o then continue_op m o else
      begin match Hash.equal (Op.hash o) Hash.nil with
      | true ->
          begin match Op.did_not_write o with
          | [] -> continue_op m o
          | miss ->
              Op.set_status o (Op.Failed (Op.Missing_writes miss));
              discontinue_op m o
          end
      | false ->
          match Reviver.record m.m.reviver o with
          | Ok true -> continue_op m o
          | Ok false ->
              let miss = Op.did_not_write o in
              Op.set_status o (Op.Failed (Op.Missing_writes miss));
              discontinue_op m o
          | Error e ->
              begin match Op.did_not_write o with
              | [] -> notify_reviver_error m `Warn o e; continue_op m o
              | miss ->
                  Op.set_status o (Op.Failed (Op.Missing_writes miss));
                  discontinue_op m o
              end
      end
  | Op.Aborted | Op.Failed _ -> discontinue_op m o
  | Op.Waiting -> assert false

  let submit_op m o = match Op.status o with
  | Op.Aborted -> finish_op m o
  | Op.Waiting ->
      begin match Reviver.hash_op m.m.reviver o with
      | Error e ->
          (* XXX Add Op.Failed_hash failure instead of abusing Op.Exec ? *)
          let status = match Op.cannot_read o with
          | [] -> Op.Failed (Op.Exec (Some (Fmt.str "op hash error: %s" e)))
          | reads -> Op.Failed (Op.Missing_reads reads)
          in
          Op.set_status o status;
          discontinue_op m o
      | Ok hash ->
          Op.set_hash o hash;
          begin match Reviver.revive m.m.reviver o with
          | Ok false -> Exec.schedule m.m.exec o
          | Ok true -> finish_op m o
          | Error e ->
              (* It's not really interesting to warn here. Also entails
                 that cache format changes trips out people a bit less. *)
              notify_reviver_error m `Info o e; Exec.schedule m.m.exec o
          end
      end
  | Op.Done | Op.Failed _ -> assert false

  (* XXX we may blow stack continuations can add which stirs.
     XXX futures make it even worse. *)

  let rec stir ~block m = match Guard.allowed m.m.guard with
  | Some o -> submit_op m o; stir ~block m
  | None ->
      match Exec.collect m.m.exec ~block with
      | Some o -> finish_op m o; stir ~block m
      | None ->
          match Rqueue.take m.m.fiber_ready with
          | Some k -> continue_fiber m k; stir ~block m
          | None -> ()

  let add_op_and_stir m o = add_op m o; stir ~block:false m

  let status m =
    B000.Op.find_aggregate_error ~ready_roots:m.m.ready_roots (ops m)

  (* Futures *)

  module Fut = struct
    type memo = t
    type 'a undet =
      { mutable awaits_det : ('a -> unit) list; (* on Det *)
        mutable awaits_set : ('a option -> unit) list; (* on Det or Never *)}

    type 'a state = Det of 'a | Undet of 'a undet | Never
    type 'a t = { mutable state : 'a state; m : memo }

    let undet () = { awaits_det = []; awaits_set = [] }
    let set f v = match f.state with
    | Undet u ->
        begin match v with
        | None ->
            f.state <- Never;
            let add_set k = Rqueue.add f.m.m.fiber_ready (fun () -> k None) in
            List.iter add_set u.awaits_set
        | Some v as set ->
            f.state <- Det v;
            let add_det k = Rqueue.add f.m.m.fiber_ready (fun () -> k v) in
            let add_set k = Rqueue.add f.m.m.fiber_ready (fun () -> k set) in
            List.iter add_det u.awaits_det;
            List.iter add_set u.awaits_set;
        end
    | Never | Det _ -> invalid_arg "fut already set"

    let create m = let f = { state = Undet (undet ()); m } in f, set f
    let ret m v = { state = Det v; m }
    let state f = f.state
    let value f = match f.state with Det v -> Some v | _ -> None
    let await f k = match f.state with
    | Det v -> Rqueue.add f.m.m.fiber_ready (fun () -> k v)
    | Undet u -> u.awaits_det <- k :: u.awaits_det
    | Never -> ()

    let await_set f k = match f.state with
    | Det v -> Rqueue.add f.m.m.fiber_ready (fun () -> k (Some v))
    | Undet u -> u.awaits_set <- k :: u.awaits_set
    | Never -> ()

    let of_fiber m k =
      let f, set = create m in
      let run () = try k (fun v -> set (Some v)) with e -> set None; raise e in
      Rqueue.add f.m.m.fiber_ready run; f
  end

  (* Notifications *)

  let notify ?k m kind fmt = Fmt.kstr (notify_op m ?k kind) fmt
  let notify_if_error m kind ~use = function
  | Ok v -> v
  | Error e -> notify_op m kind e; use

  (* Files *)

  let file_ready m p =
    (* XXX Maybe we should really test for file existence here and notify
       a failure if it doesn't exist. But also maybe we should
       introduce a stat cache and propagate it everywhere in B000.

       XXX maybe it would be better to have this as a build op but then
       we might not be that interested in repeated file_ready, e.g.
       done by multiple resolvers. Fundamentally ready_roots had
       to be added for correct "never became ready" error reports. *)
    Guard.set_file_ready m.m.guard p;
    m.m.ready_roots <- Fpath.Set.add p m.m.ready_roots

  let read m file k =
    let id = new_op_id m and created = timestamp m in
    let k o =
      let r = Op.Read.get o in
      let data = Op.Read.data r in
      Op.Read.discard_data r; k data
    in
    let o = Op.Read.v_op ~id ~mark:m.c.mark ~created ~k file in
    add_op_and_stir m o

  let wait_files m files k =
    let id = new_op_id m and created = timestamp m and k o = k () in
    let o = Op.Wait_files.v_op ~id ~mark:m.c.mark ~created ~k files in
    add_op_and_stir m o

  let write m ?(stamp = "") ?(reads = []) ?(mode = 0o644) write d =
    let id = new_op_id m and mark = m.c.mark and created = timestamp m in
    let o = Op.Write.v_op ~id ~mark ~created ~stamp ~reads ~mode ~write d in
    add_op_and_stir m o

  let copy m ?(mode = 0o644) ?linenum ~src dst =
    let id = new_op_id m and mark = m.c.mark and created = timestamp m in
    let o = Op.Copy.v_op ~id ~mark ~created ~mode ~linenum ~src dst in
    add_op_and_stir m o

  let mkdir m ?(mode = 0o755) dir k =
    let id = new_op_id m and created = timestamp m and k o = k () in
    let o = Op.Mkdir.v_op ~id ~mark:m.c.mark ~created ~k ~mode dir in
    add_op_and_stir m o

  let delete m p k =
    let id = new_op_id m and created = timestamp m and k o = k () in
    let o = Op.Delete.v_op ~id ~mark:m.c.mark ~created ~k p in
    add_op_and_stir m o

  (* FIXME better strategy to deal with builded tools. If the tool is a
     path check for readyness if not add it to the operations reads.
     I also suspect the tool lookup approach is not exactly right at
     the moment. Maybe this will clear up when we get the configuration
     story in. *)
  type _tool =
  { tool : Tool.t;
    tool_file : Fpath.t;
    tool_env : Os.Env.assignments;
    tool_stamped_env : Os.Env.assignments; }

  type tool =
  | Miss of Tool.t * string
  | Tool of _tool

  type cmd = { cmd_tool : tool; cmd_args : Cmd.t }

  let tool_env m t =
    let env = Env.env m.m.env in
    let tool_env, stamped = Tool.read_env t env in
    let forced_env = Env.forced_env m.m.env in
    let tool_env = Os.Env.override tool_env ~by:forced_env in
    let stamped = Os.Env.override stamped ~by:forced_env in
    tool_env, stamped

  let spawn_env m cmd_tool = function
  | None -> cmd_tool.tool_env, cmd_tool.tool_stamped_env
  | Some spawn_env ->
      let env = Env.env m.m.env in
      let tool_env, stamped = Tool.read_env cmd_tool.tool env in
      let forced_env = Env.forced_env m.m.env in
      let tool_env = Os.Env.override tool_env ~by:spawn_env in
      let tool_env = Os.Env.override tool_env ~by:forced_env in
      let stamped = Os.Env.override stamped ~by:spawn_env in
      let stamped = Os.Env.override stamped ~by:forced_env in
      Os.Env.to_assignments tool_env, Os.Env.to_assignments stamped

  let tool m tool =
    let cmd_tool = match Env.tool m.m.env (Tool.name tool) with
    | Error e -> Miss (tool, e)
    | Ok tool_file ->
        let tool_env, tool_stamped_env = tool_env m tool in
        let tool_env = Os.Env.to_assignments tool_env in
        let tool_stamped_env = Os.Env.to_assignments tool_stamped_env in
        Tool { tool; tool_file; tool_env; tool_stamped_env }
    in
    fun cmd_args -> { cmd_tool; cmd_args }

  let tool_opt m t = match Env.tool m.m.env (Tool.name t) with
  | Error e (* FIXME distinguish no lookup from errors *) -> None
  | Ok _ -> Some (tool m t)

  let _spawn
      m ?(stamp = "") ?(reads = []) ?(writes = []) ?writes_manifest_root ?env
      ?cwd ?stdin ?(stdout = `Ui) ?(stderr = `Ui) ?(success_exits = [0])
      ?post_exec ?k cmd
    =
    match cmd.cmd_tool with
    | Miss (tool, e) -> m.m.feedback (`Miss_tool (tool, e))
    | Tool tool ->
        let id = new_op_id m and created = timestamp m in
        let env, stamped_env = spawn_env m tool env in
        let cwd = match cwd with None -> m.m.cwd | Some d -> d in
        let k = match k with
        | None -> fun o -> ()
        | Some k ->
            fun o -> match Op.Spawn.exit (Op.Spawn.get o) with
            | Some (`Exited code) -> k code
            | _ -> assert false
        in
        let o =
          Op.Spawn.v_op
            ~id ~mark:m.c.mark ~created ~reads ~writes ?writes_manifest_root
            ?post_exec ~k ~stamp ~env ~stamped_env ~cwd ~stdin ~stdout ~stderr
            ~success_exits tool.tool_file cmd.cmd_args
        in
        add_op_and_stir m o

  let spawn
      m ?stamp ?reads ?writes ?env ?cwd ?stdin ?stdout ?stderr ?success_exits
      ?post_exec ?k cmd
    =
    _spawn m ?stamp ?reads ?writes ?env ?cwd ?stdin ?stdout ?stderr
      ?success_exits ?post_exec ?k cmd

  let spawn'
      m ?stamp ?reads ~writes_root ?writes ?env ?cwd ?stdin ?stdout ?stderr
      ?success_exits ?k cmd
    =
    let writes = match writes with
    | Some writes -> writes
    | None ->
        fun o ->
          let dotfiles = true and recurse = true in
          fail_if_error m
            Os.Dir.(fold_files ~dotfiles ~recurse path_list writes_root [])
    in
    let post_exec o =
      if B000.Op.revived o || B000.Op.status o <> B000.Op.Done then () else
      Op.set_writes o (writes o)
    in
    _spawn m ?stamp ?reads ~writes_manifest_root:writes_root ?env ?cwd ?stdin
      ?stdout ?stderr ?success_exits ~post_exec ?k cmd
end

(* Stores *)

module Store = struct
  module rec Key : sig
    type t = V : 'a typed -> t
    and 'a typed =
      { uid : int; tid : 'a Tid.t; mark : string;
        det : Store.t -> Memo.t -> 'a Memo.fiber; untyped : t; }
    val compare : t -> t -> int
  end = struct
    type t = V : 'a typed -> t
    and 'a typed =
      { uid : int; tid : 'a Tid.t; mark : string;
        det : Store.t -> Memo.t -> 'a Memo.fiber; untyped : t;}
    let compare (V l0) (V l1) = (compare : int -> int -> int) l0.uid l1.uid
  end
  and Store : sig
    module Kmap : Map.S with type key = Key.t
    type binding = B : 'a Key.typed * 'a Memo.Fut.t -> binding
    type t = { memo : Memo.t; mutable map : binding Kmap.t; dir : Fpath.t }
  end = struct
    module Kmap = Map.Make (Key)
    type binding = B : 'a Key.typed * 'a Memo.Fut.t -> binding
    type t = { memo : Memo.t; mutable map : binding Kmap.t; dir : Fpath.t }
  end

  type 'a key = 'a Key.typed
  type binding = B : 'a key * 'a -> binding
  type t = Store.t

  let create memo ~dir bs =
    let add m (B (k, v)) =
      Store.Kmap.add k.untyped (Store.B (k, Memo.Fut.ret memo v)) m
    in
    let map = List.fold_left add Store.Kmap.empty bs in
    { Store.memo; map; dir : Fpath.t; }

  let memo s = s.Store.memo
  let dir s = s.Store.dir

  let key_uid = let id = ref (-1) in fun () -> incr id; !id
  let key ?(mark = "") det =
    let uid = key_uid () and tid = Tid.create () in
    let rec k = { Key.uid; tid; mark; det; untyped }
    and untyped = Key.V k in k

  let get : type a. t -> a key -> a Memo.fiber =
  fun s k -> match Store.Kmap.find k.Key.untyped s.map with
  | exception Not_found ->
      let memo = Memo.with_mark s.memo k.Key.mark in
      let fut = Memo.Fut.of_fiber memo (k.Key.det s memo) in
      s.map <- Store.Kmap.add k.Key.untyped (Store.B (k, fut)) s.map;
      Memo.Fut.await fut
  | Store.B (l', fut) ->
      match Tid.equal k.Key.tid l'.Key.tid with
      | None -> assert false
      | Some Tid.Eq -> Memo.Fut.await fut
end

(*---------------------------------------------------------------------------
   Copyright (c) 2018 The b0 programmers

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
