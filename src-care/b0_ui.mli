(*---------------------------------------------------------------------------
   Copyright (c) 2018 The b0 programmers. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
   %%NAME%% %%VERSION%%
  ---------------------------------------------------------------------------*)

(** User interaction fragments.

    User interaction fragments for devising build tools. *)

(** {1:ui User interaction fragments} *)

open B0_std
open Cmdliner

(** Signal exit hooks. *)
module Sig_exit : sig

  val on_sigint :  hook:(unit -> unit) -> (unit -> 'a) -> 'a
  (** [on_sigint ~hook f] calls [f ()] and returns its value. If [SIGINT]
      is signalled during that time [hook] is called followed by [exit 130]
      – that is the exit code a [SIGINT] would produce.

      [on_sigint] replaces an existing signal handler for
      {!Sys.sigint} during time of the function call. It is restored
      when the function returns.

      {b Note.} Since {!exit} is called {!at_exit} functions are
      called if a [SIGINT] occurs during the function call. This is not
      the case on an unhandled [SIGINT]. *)
end

(** {!Cmdliner} fragments. *)
module Cli : sig

  (** Miscellaneous {!Cmdliner} argument converters. *)
  module Arg : sig

    val fpath : Fpath.t Arg.conv
    (** [fpath] is a converter for file paths. No existence checks are
        performed on the path. *)

    val cmd : Cmd.t Arg.conv
    (** [cmd] is a converter for commands. *)
  end

  (** {1:out_fmt Specifying output formats} *)

  type out_fmt = [ `Normal | `Short | `Long ]
  (** The type for specifying output format details. *)

  val out_fmt :
    ?docs:string -> ?short_opts:string list -> ?long_opts:string list ->
    unit -> out_fmt Term.t
  (** [out_fmt ~short_opts ~long_opts ()] are mutually exclusive options
      to specify short and long output format, without options this is
      [`Normal]. [short_opts] defaults to [["s"; "short"]] and
      [long_opts] default to [["l"; "long"]]. [docs] is the manual section
      in which options are documtend. *)
end

(** {!B0_std} configuration.

    Configure {!B0_std}'s colored output and {!B0_std.Log} verbosity. *)
module B0_std : sig

  (** {1:cli Cli arguments} *)

  val color :
    ?docs:string -> ?env:Cmdliner.Arg.env -> unit -> Tty.cap option Term.t
  (** [color ~docs ~env] is a cli interface for specifiying the color
      capability of the terminal. Can be used with
      {!Fmt.set_tty_styling_cap}. [docs] is where the options are
      documented [env] is an environment variable that can be used to
      override the default [None] (auto configuration). *)

  val verbosity :
    ?docs:string -> ?env:Cmdliner.Arg.env -> unit -> Log.level Term.t
  (** [verbosity ~docs ~env ()] is a cli interface for specifiying the
      logging level. Can be used with {!Log.set_level}. [docs] is
      where the options are documented. [env] is an environment
      variable that can be used to override the default value
      ({!Log.Warning}). *)

  val cli_setup :
    ?docs:string -> ?log_spawns:Log.level -> ?color_env:Cmdliner.Arg.env ->
    ?verbosity_env:Cmdliner.Arg.env -> unit -> unit Term.t
    (** [setup ~docs ~log_spawns ~color_env ~verbosity_env ()] uses
        {!color} and {!verbosity} to setup:
        {ul
        {- {!B0_std.Fmt.set_tty_styling_cap}, using {!Tty.of_fd}
            on {!Unix.stdout} if {!color} is [None].}
        {- {!B0_std.Log.set_level} with {!verbosity}.}
        {- [log_spawns] log {!B0_std.Os.Cmd} spawns by setting up
            a {!B0_std.Os.Cmd.spawn_tracer} that traces with the given level.
            If [Level.Quiet] is specified no tracer is registered. Defaults
            to {!B0_std.Log.Debug}.}}
        [docs] is where the section in which the options are documented
        and [color_env] and [verbosity_env] are used with the [env]
        argument of {!color} and {!verbosity}. *)
end

(** {!B00.File_cache} interaction. *)
module File_cache : sig

  (** {1:high-level High-level commands.}

      These commands act on a cache directory. They avoid to create
      it via {!B00.File_cache.create} if it doesn't exists and mostly
      return [Ok ()] in these cases. *)

  val delete :
    dir:Fpath.t -> [ `All | `Keys of B000.File_cache.key list ] ->
    (unit, string) result
  (** [delete dir keys] deletes [keys] in [dirs] if an explicit key
      does not exist in [dir] a {!Log.warn} is issued. If [`All] is
      specified [dir] is deleted and recreated. *)

  val gc : dir:Fpath.t -> (unit, string) result
  (** [gc dir] deletes unused keys via {!B00.File_cache.delete_unused}. *)

  val size : dir:Fpath.t -> (unit, string) result
  (** [size dir] shows statistics about the file cache on stdout
      via {!B00.File_cache.Stats.pp}. *)

  val trim :
    dir:Fpath.t -> max_byte_size:int -> pct:int -> (unit, string) result
    (** [trim dir ~max_byte_size ~pct] trims the cache using
        {!B00.File_cache.trim_size}. *)

  (** {1:cli Cli fragments} *)

  val key_arg : B000.File_cache.key Cmdliner.Arg.conv
  (** [key_arg] is an argument converter for cache keys. *)

  val keys_none_is_all :
    ?pos_right:int -> unit ->
    [ `All | `Keys of B000.File_cache.key list ] Cmdliner.Term.t
   (** [keys_none_is_all ~pos_right ()] are the keys at the right
       of position [pos_right] (defaults is all positional arguments).
       If none is specified this is [`All]. *)
end


(** {!B000.Op} interaction. *)
module Op : sig

  val is_selected :
    reads:Fpath.t list -> writes:Fpath.t list -> ids:B000.Op.id list ->
    hashes:string list -> groups:string list -> B000.Op.t -> bool
  (** [is_selected ~reads ~writes ~ids ~hashes ~groups o] is [true]
      iff [o] reads a file in [reads] or writes a file in [writes]
      or has its id in [ids], or has its hash in [hashes] or has
      is [group] in [groups] or if all these lists are empty. *)

  val order :
    by:[`Create | `Dur | `Wait | `Start] -> B000.Op.t list -> B000.Op.t list
  (** [order ~by ops] orders [ops] by [by] time. *)

  val read_write_indexes :
    B000.Op.t list -> B000.Op.Set.t Fpath.Map.t * B000.Op.Set.t Fpath.Map.t
  (** [read_write_indexes ops] is [reads, writes] with [reads] mapping
      file path to operations that reads them and [writes] mapping file
      paths to operations that write them. *)

  val find_needs :
    ?acc:B000.Op.Set.t -> recursive:bool -> writes:B000.Op.Set.t Fpath.Map.t ->
    B000.Op.Set.t -> B000.Op.Set.t
  (** [find_needs ~recursive ~writes ~acc ops] add to [acc] (defaults
      to {!B00.Op.Set.empty}) the set of operations in the write index
      [writes] that need to be executed for the set of operations
      [ops] to be able to proceed. If [recursive] is [false] only direct
      dependencies are reported. *)

  val find_enables :
    ?acc:B000.Op.Set.t -> recursive:bool ->
    reads:B000.Op.Set.t Fpath.Map.t -> B000.Op.Set.t -> B000.Op.Set.t
    (** [find_enables ~recursive ~writes ~acc ops] add to [acc]
      (defaults to {!B00.Op.Set.empty}) the set of operations in the
      read index [reads] that are enabled by the set of operations
      [ops]. If [recursive] is [false] only direct dependencies are
        reported. *)

  val select :
    reads:Fpath.t list -> writes:Fpath.t list -> ids:B000.Op.id list ->
    hashes:string list -> groups:string list -> needs:bool -> enables:bool ->
    recursive:bool -> revived:bool option ->
    status:[`Aborted | `Done | `Failed | `Waiting ] option ->
    order_by:[ `Create | `Dur | `Wait | `Start ] -> B000.Op.t list ->
    B000.Op.t list

  val select_cli : (B000.Op.t list -> B000.Op.t list) Cmdliner.Term.t
end

(** {!B00.Memo} interaction. *)
module Memo : sig

  (** {1:feedback Memo feedback} *)

  val pp_leveled_feedback :
    ?sep:unit Fmt.t -> ?op_howto:B000.Op.t Fmt.t -> show_op:Log.level ->
    show_ui:Log.level -> level:Log.level ->
    [B00.Memo.feedback | B000.File_cache.feedback | B000.Exec.feedback] Fmt.t
  (** [pp_leveled_feedback ~sep ~op_howto ~show_spawn_ui ~show_success ~level
      ppf] formats memo feedback on [ppf] followed by [sep] iff something
      is printed (defaults to {!Fmt.flush_nl}).
      {ul
      {- {!Log.Quiet} formats nothing}
      {- {!Log.Debug} report all operations with {!B000_conv.Op.pp_short_ui}.}}
      {ul
      {- [show_ui] is the level at which any completed operation
         gets logged with {!B000_conv.Op.pp_ui}.}
      {- [show_op] is the level at which any completed operation gets
         logged with {!B000_conv.Op.pp_short_ui}}}
      The formatter [op_howto] should format a way to got more information
      about an operation, default to {!nop}. *)

  val pp_error :
    ?sep:unit Fmt.t -> ?read_howto:Fpath.t Fmt.t ->
    ?write_howto:Fpath.t Fmt.t -> unit ->  B00.Memo.error Fmt.t
  (** [pp_error ~read_howto ~write_howto] formats a memo
      error followed by [sep] iff somethings is printed (defaults
      to {!Fmt.flush_nl}). The errors are formatted as follows:
      {ul
      {- {!B00.Memo.Failures} formats {!Fmt.nop}.}
      {- {!B00.Memo.Never_became_ready} formats each file
         prefixing it with [op_reading_howto].}
      {- {!B00.Memo.Cycle}, formats the operations of the cycle.}} *)

  (** {1:dirs_files Specifying directories and files} *)

  val b0_dir_name : string
  (** [b0_dir_name] is ["_b0"] the default b0 directory name. *)

  val cache_dir_name : string
  (** [cache_dir_name] is [".cache"] the default cache directory name
      in the [b0] directory. *)

  val trash_dir_name : string
  (** [trash_dir_name] is [".trash"] the default trash directoy name
      in the [b0] directory. *)

  val log_file_name : string
  (** [log_file_name] is [".log"] the default log file name in
      the [b0] directory. *)

  val b0_dir_env : string
  (** [b0_dir_env] is ["B0_DIR"]. *)

  val cache_dir_env : string
  (** [b0_dir_env] is ["B0_CACHE_DIR"]. *)

  val log_file_env : string
  (** [b0_dir_env] is ["B0_LOG_FILE"]. *)

  val b0_dir :
    ?docs:string -> ?doc:string -> ?doc_none:string -> ?env:Cmdliner.Arg.env ->
    unit -> Fpath.t option Term.t
  (** [b0_dir ~doc_none ~docs ~doc ~env] is a cli interface for specifying
      a b0 directory.
      {ul
      {- [docs] is where the option is documented, defaults to
         {!Manpage.s_common_options}}
      {- [doc] is a doc string.}
      {- [doc_none] describes how the value is determined if the term is
         evaluates to [None].}
      {- [env] is a variable that can be used to override the default
         value, defaults to {!b0_dir_env}.}} *)

  val cache_dir :
    ?opts:string list -> ?docs:string -> ?doc:string -> ?doc_none:string ->
    ?env:Cmdliner.Arg.env -> unit -> Fpath.t option Term.t
  (** [cache_dir ~doc_none ~docs ~doc ~env] is a cli interface for specifying
      a b0 cache directory.
      {ul
      {- [opts] are the cli options to specify it.}
      {- [docs] is where the option is documented, defaults to
         {!Manpage.s_common_options}}
      {- [doc] is a doc string.}
      {- [doc_none] describes how the value is determined if the term is
         evaluates to [None].}
      {- [env] is a variable that can be used to override the default
         value, defaults to {!cache_dir_env}.}} *)

  val log_file :
    ?opts:string list -> ?docs:string -> ?doc:string -> ?doc_none:string ->
    ?env:Cmdliner.Arg.env -> unit -> Fpath.t option Term.t
  (** [log_file ~doc_none ~docs ~doc ~env] is a cli interface for
      specifing a b0 log file.
      {ul
      {- [opts] are the cli options to specify it.}
      {- [docs] is where the option is documented, defaults to
         {!Manpage.s_common_options}}
      {- [doc] is a doc string.}
      {- [doc_none] describes how the value is determined if the term is
         evaluates to [None].}
      {- [env] is a variable that can be used to override the default
         value, defaults to {!cache_dir_env}.}} *)

  val get_b0_dir :
    cwd:Fpath.t -> root:Fpath.t -> b0_dir:Fpath.t option -> Fpath.t
  (** [get_b0_dir ~cwd ~root ~b0_dir] determines a b0 directory. If
      [b0_dir] is [Some d] then this is [Fpath.(cwd // d)]. If [None]
      then this is [Fpath.(root / b0_dir_name)]. *)

  val get_cache_dir :
    cwd:Fpath.t -> b0_dir:Fpath.t -> cache_dir:Fpath.t option -> Fpath.t
  (** [get_cache_dir ~cwd ~b0_dir ~cache_dir] determines a cache directory.
      If [cache_dir] is [Some d] then this is [Fpath.(cwd // d)]. If [None]
      then this is [Fpath.(b0_dir / cache_dir)]. *)

  val get_trash_dir :
    cwd:Fpath.t -> b0_dir:Fpath.t -> trash_dir:Fpath.t option -> Fpath.t
  (** [get_trash_dir ~cwd ~b0_dir ~trash_dir] dtermiens a trash directory.
      If [trash_dir] is [Some d] then this is [Fpath.(cwd // d]. If
      [None] then this is [Fpath.(b0_dir /trash_dir)]. *)

  val get_log_file :
    cwd:Fpath.t -> b0_dir:Fpath.t -> log_file:Fpath.t option -> Fpath.t
  (** [get_log_file ~cwd ~b0_dir ~log_file] determines a log file.
      If [log_file] is [Some f] then this is [Fpath.(cwd // f)]. If [None]
      then this is [Fpath.(b0_dir /log_file)]. *)

  (** {1:build Build parameters} *)

  val jobs : ?docs:string -> ?env:Arg.env -> unit -> int option Term.t
  (** [jobs] is a cli interface for specifying the maximal number of
      commands to spawn concurrently. *)

  val find_jobs : jobs:int option -> unit -> int
  (** [fin_jobs jobs] determines a maximal number of spans. This is
      either, in order, [jobs] or {!B0_machine.logical_cpu_count} or
      [1]. *)

  (** {1:build_log Build log} *)

  module Log : sig

    type info
    val write_file : Fpath.t -> B00.Memo.t -> (unit, string) result
    val read_file : Fpath.t -> (info * B000.Op.t list, string) result

    type out_fmt = [`Long | `Normal | `Short | `Trace_event | `Stats ]
    val out : out_fmt -> (out_fmt * (info * B000.Op.t list -> unit))
    val out_fmt_cli :
      ?docs:string -> unit ->
      (out_fmt * (info * B000.Op.t list -> unit)) Cmdliner.Term.t

    val pp_stats : (info * B000.Op.t list) Fmt.t
    (** [pp_stats] formats statistics about the memoizer. *)
  end
end

(** Pager interaction. *)
module Pager : sig

  (** {1:cli Cli arguments} *)

  val envs : Term.env_info list
  (** [envs] describe the [PAGER] and [TERM] environment variable. *)

  val don't : ?docs:string -> unit -> bool Term.t
  (** [don't ~docs ()] is a [--no-pager] command line option to
      unconditionally request not use a pager. [docs] is the manual
      section where the option is documented. *)

  (** {1:pager Pager} *)

  val find :
    ?search:Fpath.t list -> don't:bool -> unit -> (Cmd.t option, string) result
  (** [find ~search ~don't] finds a suitable pager. This is (in order):
      {ol
      {- [Ok None] if [don't] is [true] or if the [TERM] environment variable
         is [dumb] or undefined.}
      {- [Ok (Some pager)] if [pager] is a tool invocation parsed from the
         [PAGER] environment variable that can be found via
         [Os.Cmd.find ?search].}
      {- [Ok (Some pager)] if either [less] or [more] can be found
         (in that order) via [Os.Cmd.find ?search].}
      {- [Ok None] otherwise.}} *)

  val page_stdout : Cmd.t option -> (unit, string) result
  (** [page_stdout pager] setups the program so that if [pager] is
      [Some cmd], the standard output of the program is redirected to
      a spawn of [cmd] with the following twists:
      {ul
      {- If the environment variable [LESS] is undefined in the
         current environment it is set to [LESS=FRX] for the spawn of
         [cmd].}
      {- A {!Pervasive.at_exit} function is installed that flushes
         {!Fmt.stdout} and {!stdout}, closes [Unix.stdout] and waits
         upon the [cmd] spawn termination.}}
      If [pager] is [None] this function has no effect. *)

  val page_files : Cmd.t option -> Fpath.t list -> (unit, string) result
  (** [page_files pager fs] uses [pager] to page the files [fs]. If [pager]
      is:
      {ul
      {- [None], each of the [fs] files is output on stdout in order
         separated by a file separator character (U+001C).}
      {- [Some cmd], [cmd] is run with [fs] as arguments. If [fs]
         is empty does nothing.}} *)
end

(** Editor interaction. *)
module Editor : sig

  (** {1:cli Cli arguments} *)

  val envs : Term.env_info list
  (** [envs] describe the [VISUAL] and [EDITOR] environment variable. *)

  (** {1:editor Editor} *)

  val find :
    ?search:Fpath.t list -> unit -> (Cmd.t option, string) result
  (** [find ?search ~don't] finds a suitable editor. This is (in order):
      {ol
      {- [Ok (Some pager)] if [pager] is a tool invocation parsed from the
         [VISUAL] environment variable that can be found via
         [Os.Cmd.find ?search].}
      {- [Ok (Some pager)] if [pager] is a tool invocation parsed from the
         [EDITOR] environment variable that can be found via
         [Os.Cmd.find ?search].}
      {- [Ok (Some pager)] if [nano] can be found via [Os.Cmd.find ?search].}
      {- [Ok None] otherwise.}} *)

  val edit_files :
    Cmd.t option -> Fpath.t list -> (Os.Cmd.status, string) result
  (** [edit-files editor fs] uses [editor] to edit the files [fs]. If [editor]
      is:
      {ul
      {- [None], an error message is returned mentioning that no editor
         was found.}
      {- [Some editor] invokes the command with files [fs] and returns the
         exit status of the program.}} *)
end

(** PDF viewer interaction. *)
module Pdf_viewer : sig

  (** {1:cli Cli arguments} *)

  val pdf_viewer :
    ?docs:string -> ?opts:string list -> unit -> Cmd.t option Term.t
  (** [pdf_viewer ~docs ~opts ()] is an option and [PDFVIEWER] environment
      variable to use with [pdf_viewer] argument of {!find}. [opts] are
      the cli options and default to ["pdf-viewer"]. *)

  (** {1:pdf Show PDFs} *)

  type t
  (** The type for specifying a PDF viewer. *)

  val find :
    ?search:Fpath.t list -> pdf_viewer:Cmd.t option -> unit ->
    (t option, string) result
  (** [find ~search ~pdf_viewer] tries to find a PDF viewer in a platform
      dependent way. *)

  val show : t option -> Fpath.t -> (unit, string) result
  (** [show pdf_viewer file] shows PDF file using the viewer
      [pdf_viewer] (if [None] an error message is returned mentioning
      no viewer was found). *)
end

(** Web browser interaction.

    [Browser] shows URIs in the user's browsers. Up to severe
    platform and browser application limitation it tries to limit
    the creation of new tabs, reloading existing one which have the
    same URI or are, if requested, prefixed by the URI. *)
module Browser : sig

  (** {1:cli Cli arguments} *)

  val browser : ?docs:string -> ?opts:string list -> unit -> Cmd.t option Term.t
  (** [browser] is an option and [BROWSER] environment variable to use
      with the [browser] argument of {!find}. [opts] are the cli
      options and default to [["browser"]]. *)

  val prefix :  ?docs:string -> ?opts:string list -> unit -> bool Term.t
  (** [prefix] is  option to use the with [prefix] argument of
      {!show}. [opts] are the cli options and default to
      [["prefix"]]. *)

  val background : ?docs:string -> ?opts:string list -> unit -> bool Term.t
  (** [background] is an option to use with the [background] argument
      of [!show]. [opts] are the cli options and default to [["background"]] *)

  (** {1:show Show URIs} *)

  type t
  (** The type for specifying a browser. *)

  val find :
    ?search:Fpath.t list -> browser:Cmd.t option -> unit ->
    (t option, string) result
  (** [find ~search ~browser] tries to find a browser in a rather
      complex and platform dependent way. *)

  val show :
    background:bool -> prefix:bool -> t option -> string ->
    (unit, string) result
   (** [show ~background ~prefix browser uri] shows URI using browser
       [browser] (if [None] an error message is returned mentioning
       that no browser was found. If [background] is [true] tries to
       keep the browser application in the background, if [false]
       brings it in user focus.

       The function tries to limit the creation of new tabs using the
       following strategy:
       {ul
       {- Repeat from the frontmost browser window to the backmost one until
       a tab to reload is found:
       {ol
       {- If the window's current tab's URI is [uri] (or is prefixed by [uri]
          when  [prefix] is [true]), reload this tab.}
       {- If the window has one or more tab whose URI is [uri] (or is prefixed
          by [uri] when [prefix] is [true]), pick the left most one, make it
         current in the window and reload it.}}}
       {- If no tab was found, get the frontmost window. If the current tab
          has no URI, use that tab with [uri] otherwise create a new tab
          with [uri] and make it current for the window.}} *)
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
