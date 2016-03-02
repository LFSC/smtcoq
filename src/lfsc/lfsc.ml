(**************************************************************************)
(*                                                                        *)
(*     SMTCoq                                                             *)
(*     Copyright (C) 2011 - 2016                                          *)
(*                                                                        *)
(*     Michaël Armand                                                     *)
(*     Benjamin Grégoire                                                  *)
(*     Chantal Keller                                                     *)
(*                                                                        *)
(*     Inria - École Polytechnique - MSR-Inria Joint Lab                  *)
(*     Université Paris-Sud                                               *)
(*                                                                        *)
(*   This file is distributed under the terms of the CeCILL-C licence     *)
(*                                                                        *)
(**************************************************************************)


open Entries
open Declare
open Decl_kinds

open SmtMisc
open CoqTerms
open SmtForm
open SmtCertif
open SmtTrace
open SmtAtom


(******************************************************************************)
(* Given a lfsc trace build the corresponding certif and theorem             *)
(******************************************************************************)

(* TODO: replace these dummy functions with complete ones *)

let import_trace filename =
  let chan = open_in filename in
  let lexbuf = Lexing.from_channel chan in
  let _ = LfscParser.certif LfscLexer.token lexbuf in
  ()


let clear_all () =
  SmtTrace.clear ();
  LfscSyntax.clear ()


let import_all fsmt fproof =
  clear_all ();
  let rt = Btype.create () in
  let ro = Op.create () in
  let ra = LfscSyntax.ra in
  let rf = LfscSyntax.rf in
  let roots = Smtlib2_genConstr.import_smtlib2 rt ro ra rf fsmt in
  let () = import_trace fproof in
  ()


(* let parse_certif t_i t_func t_atom t_form root used_root trace fsmt fproof = *)
(*   SmtCommands.parse_certif t_i t_func t_atom t_form root used_root trace (import_all fsmt fproof) *)
(* let theorem name fsmt fproof = SmtCommands.theorem name (import_all fsmt fproof) *)
(* let checker fsmt fproof = SmtCommands.checker (import_all fsmt fproof) *)
let checker fsmt fproof =
  let () = import_all fsmt fproof in
  Format.eprintf "     = %s\n     : bool@." "false"



(******************************************************************************)
(** Given a Coq formula build the proof                                       *)
(******************************************************************************)

(* TODO *)
