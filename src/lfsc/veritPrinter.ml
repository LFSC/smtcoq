(**************************************************************************)
(*                                                                        *)
(*                            LFSCtoSmtCoq                                *)
(*                                                                        *)
(*                         Copyright (C) 2016                             *)
(*          by the Board of Trustees of the University of Iowa            *)
(*                                                                        *)
(*                    Alain Mebsout and Burak Ekici                       *)
(*                       The University of Iowa                           *)
(*                                                                        *)
(*                                                                        *)
(*  This file is distributed under the terms of the Apache Software       *)
(*  License version 2.0                                                   *)
(*                                                                        *)
(**************************************************************************)

open Format
open Ast
open Builtin
open Translator_sig  


type lit = term

type clause = term list

(* module HT = Hashtbl.Make (Term) *)
(* module HT = struct *)
(*   include Hashtbl.Make (Term) *)
(*   let add h k v = flatten_term k; add h k v *)
(*   let find h k = flatten_term k; find h k *)
(* end *)

(* module HCl = Hashtbl.Make (struct *)
(*     type t = clause *)
(*     let equal c1 c2 = compare_term_list c1 c2 = 0 *)
(*     let hash = List.fold_left (fun acc t -> Term.hash t + acc) 0  *)
(*   end) *)

module HS = Hashtbl

module HT = struct
  module M = Map.Make (Term)
  let create _ = ref M.empty
  let add h k v = h := M.add k v !h
  let find h k = M.find k !h
  let clear h = h := M.empty
  let iter f h = M.iter f !h
end

module HCl = struct
  module M = Map.Make (struct
      type t = clause
      let compare c1 c2 = compare_term_list c1 c2
    end)
  let create _ = ref M.empty
  let add h k v = h := M.add k v !h
  let find h k = M.find k !h
  let clear h = h := M.empty
  let iter f h = M.iter f !h
end


let fmt = std_formatter

let clauses_ids = HCl.create 201
let ids_clauses = Hashtbl.create 201
let propvars = HT.create 201
let sharp_tbl = HT.create 13
let inputs : (string, int) Hashtbl.t = HS.create 13
let alias_tbl = HS.create 17
(* let termalias_tbl = HT.create 17 *)

let cpt = ref 0
let cl_cpt = ref 0




let get_rule = function
  | Reso -> "resolution"
  | Weak -> "weaken"
  | Or -> "or"
  | Orp -> "or_pos"
  | Imp -> "implies"
  | Impp -> "implies_pos"
  | Nand -> "not_and"
  | Andn -> "and_neg"
  | Nimp1 -> "not_implies1"
  | Nimp2 -> "not_implies2"
  | Impn1 -> "implies_neg1"
  | Impn2 -> "implies_neg2"
  | Nor -> "not_or"
  | Orn -> "or_neg"
  | And -> "and"
  | Andp -> "and_pos"
  | Equ1 -> "equiv1"
  | Equ2 -> "equiv2"
  | Nequ1 -> "not_equiv1"
  | Nequ2 -> "not_equiv2"
  | Equp1 -> "equiv_pos1"
  | Equp2 -> "equiv_pos2"
  | Equn1 -> "equiv_neg1"
  | Equn2 -> "equiv_neg2"
  | Xor1 -> "xor1"
  | Xor2 -> "xor2"
  | Xorp1 -> "xor_pos1"
  | Xorp2 -> "xor_pos2"
  | Xorn1 -> "xor_neg1"
  | Xorn2 -> "xor_neg2"
  | Nxor1 -> "not_xor1"
  | Nxor2 -> "not_xor2"
  | Itep1 -> "ite_pos1"
  | Itep2 -> "ite_pos2"
  | Iten1 -> "ite_neg1"
  | Iten2 -> "ite_neg2"
  | Ite1 -> "ite1"
  | Ite2 -> "ite2"
  | Nite1 -> "not_ite1"
  | Nite2 -> "not_ite2"
  | Eqtr -> "eq_transitive"
  | Eqcp -> "eq_congruent_pred"
  | Eqco -> "eq_congruent"
  | Eqre -> "eq_reflexive"
  | Lage -> "la_generic"
  | Flat -> "flatten"
  | Hole -> "hole"
  | True -> "true"
  | Fals -> "false"
  | Bbva -> "bbvar"
  | Bbconst -> "bbconst"
  | Bbeq -> "bbeq"
  | Bbdis -> "bv_const_neq"
  | Bbop -> "bbop"
  | Bbadd -> "bbadd"
  | Bbmul -> "bbmul"
  | Bbult -> "bbult"
  | Bbslt -> "bbslt"
  | Bbnot -> "bbnot"
  | Bbneg -> "bbneg"
  | Bbconc -> "bbconcat"
  | Row1 -> "row1"
  | Row2 -> "row2" 
  | Exte -> "ext" 



let print_sharps () =
  HT.iter (fun t id ->
      printf "#%d --> %a@." id Ast.print_term_type t) sharp_tbl


let smt2_of_lfsc = function
  | "iff" -> "="
  | "ifte" -> "ite"
  | "flet" -> "let"
  | "impl" -> "=>"
  | ">_Int" -> ">"
  | ">=_Int" -> ">="
  | "<_Int" -> "<"
  | "<=_Int" -> "<="
  | "+_Int" -> "+"
  | "-_Int" -> "-"
  | "*_Int" -> "*"
  | "/_Int" -> "/" (* Maybe div? *)
  | "u-_Int" -> "-"
  | t -> t


let new_sharp t =
  incr cpt;
  HT.add sharp_tbl t !cpt;
  !cpt


let print_bit fmt b = match name b with
  | Some "b0" -> fprintf fmt "0"
  | Some "b1" -> fprintf fmt "1"
  | _ -> assert false

let rec print_bv_const fmt t = match name t with
  | Some "bvn" -> ()
  | _ -> match app_name t with
    | Some ("bvc", [b; t]) ->
      fprintf fmt "%a%a" print_bit b print_bv_const t
    | _ -> assert false

let rec print_apply fmt t = match app_name t with
  | Some ("apply", [_; _; f; a]) ->
    fprintf fmt "%a %a" print_apply f print_term a
  | _ -> print_term fmt t
  

(* Endianness dependant: LFSC big endian -> SMTCoq little endian *)
and print_bblt fmt t = match name t with
  | Some "bbltn" -> ()
  | _ -> match app_name t with
    | Some ("bbltc", [f; r]) ->
      fprintf fmt "%a %a" print_bblt r print_term f
    | _ -> assert false


and print_term fmt t =
  try HT.find sharp_tbl t |> fprintf fmt "#%d" with Not_found ->
  (* try HT.find termalias_tbl (deref t) |> print_term fmt with Not_found -> *)
    match value t with
    | Int n -> fprintf fmt "%s" (Big_int.string_of_big_int n)
    | _ ->
    match name t with
    | Some n ->
      begin
        try
          print_term fmt (HS.find alias_tbl n)
        with Not_found -> pp_print_string fmt (smt2_of_lfsc n)
      end
    | None -> match app_name t with

      | Some ("=", [ty; a; b]) ->
        let eqt = match value t with App (eqt, _ ) -> eqt | _ -> assert false in
        incr cpt;
        let eq_b_a = mk_app eqt [ty; b; a] in
        HT.add sharp_tbl t !cpt;
        HT.add sharp_tbl eq_b_a !cpt;
        (* let a, b = if compare_term a b <= 0 then a, b else b, a in *)
        fprintf fmt "#%d:(= %a %a)" !cpt print_term a print_term b

      | Some ("not", [a]) -> fprintf fmt "(not %a)" print_term a
                               
      | Some ("apply", _) ->
        let nb = new_sharp t in
        fprintf fmt "#%d:(%a)" nb print_apply t

      | Some ("p_app", [a]) -> print_term fmt a

      | Some ("a_int", [{value = Int n}]) ->
        fprintf fmt "%s" (Big_int.string_of_big_int n)

      | Some ("a_var_bv", [_; a]) -> print_term fmt a

      | Some ("a_bv", [_; a]) -> print_term fmt a

      | Some ("bvc", _) -> fprintf fmt "#b%a" print_bv_const t

      | Some (("bvand"|"bvor"|"bvxor"|"bvadd"|"bvmul"|"bvult"|"bvslt"|"bvule"|"bvsle") as op,
              [_; a; b]) ->
        let nb = new_sharp t in
        fprintf fmt "#%d:(%s %a %a)" nb op print_term a print_term b

      | Some (("bvnot"|"bvneg") as op, [_; a]) ->
        let nb = new_sharp t in
        fprintf fmt "#%d:(%s %a)" nb op print_term a

      | Some ("concat" as op, [_; _; _; a; b]) ->
        let nb = new_sharp t in
        fprintf fmt "#%d:(%s %a %a)" nb op print_term a print_term b

      | Some ("bitof", [a; {value = Int n}]) ->
        let nb = new_sharp t in
        fprintf fmt "#%d:(bitof %s %a)" nb
          (Big_int.string_of_big_int n) print_term a

      | Some ("bbltc", _) -> fprintf fmt "[%a]" print_bblt t

      | Some ("bblast_term", [_; a; bb]) ->
        let nb = new_sharp t in
        fprintf fmt "#%d:(bbT %a [%a])" nb print_term a print_bblt bb

      | Some ("read", [_; _]) -> fprintf fmt "select"
      | Some ("write", [_; _]) -> fprintf fmt "store"
      | Some ("diff", [_; _]) -> fprintf fmt "diff"

      | Some (n, l) ->
        let n = smt2_of_lfsc n in
        let nb = new_sharp t in
        fprintf fmt "#%d:(%s%a)" nb n
          (fun fmt -> List.iter (fprintf fmt " %a" print_term)) l

      | None ->
        eprintf "Could not translate term %a@." Ast.print_term t;
        assert false


let print_term fmt t = print_term fmt t (* (get_real t) *)


let rec print_clause elim_or fmt t = match name t with
  | Some "cln" | Some "false" -> ()
  | Some n -> pp_print_string fmt (smt2_of_lfsc n)
  | None ->
    match app_name t with
    | Some ("pos", [v]) ->
      let t = HT.find propvars (deref v) in
      fprintf fmt "%a" print_term t
    | Some ("neg", [v]) ->
      let t = HT.find propvars (deref v) in
      fprintf fmt "(not %a)" print_term t
    | Some ("clc", [a; cl]) ->
      fprintf fmt "%a %a" (print_clause elim_or) a (print_clause elim_or) cl
    | Some ("or", [a; b]) when elim_or ->
      fprintf fmt "%a %a" (print_clause elim_or) a (print_clause elim_or) b
    | _ -> fprintf fmt "%a" print_term t


let print_clause_elim_or fmt t = fprintf fmt "(%a)" (print_clause true) t

let print_clause fmt t = fprintf fmt "(%a)" (print_clause false) t
  

let rec to_clause acc t = match name t with
  | Some "cln" | Some "false" -> acc
  | Some n -> t :: acc
  | None ->
    match app_name t with
    | Some ("pos", [v]) ->
      let t = HT.find propvars (deref v) in
      t :: acc
    | Some ("neg", [v]) ->
      let t = HT.find propvars (deref v) |> not_ in
      t :: acc
    | Some ("clc", [a; cl]) ->
      to_clause (to_clause acc a) cl
    | Some ("or", [a; b]) ->
      to_clause (to_clause acc a) b
    | _ -> t :: acc


let to_clause = to_clause [] 


let rec print_clause fmt = function
  | [] -> ()
  | [t] -> print_term fmt t
  | t :: cl -> fprintf fmt "%a %a" print_term t print_clause cl

let print_clause fmt = fprintf fmt "(%a)" print_clause


let th_res p = match app_name (deref p).ttype with
  | Some ("th_holds", [r]) -> r
  | _ -> assert false


type clause_res_id = NewCl of int | OldCl of int


let clause_mod_eqsymm cl =
  List.fold_left (fun acc t -> match app_name t with
      | Some ("=", [ty; a; b]) ->
        let eqt = match value t with App (eqt, _ ) -> eqt | _ -> assert false in
        let eq_b_a = mk_app eqt [ty; b; a] in
        let acc2 = List.map (fun cl -> eq_b_a :: cl) acc in
        let acc1 = List.map (fun cl -> t :: cl) acc in
        List.rev_append acc2 acc1
      | _ -> List.map (fun cl -> t :: cl) acc
    ) [[]] cl


      
let rec normalize_eq_symm p = match app_name p with
  | Some ("=", [ty; a; b]) when compare_term a b > 0 ->
    let eqt = match value p with App (eqt, _ ) -> eqt | _ -> assert false in
    mk_app eqt [ty; b; a]
  | _ -> match p.value with
    | App (f, args) ->
      let nargs = List.map normalize_eq_symm args in
      if List.for_all2 (==) args nargs then p
      else mk_app f nargs
    | Pi (s, x) ->
      let x' = normalize_eq_symm x in
      if x == x' then p else mk_pi s x'
    | Lambda (s, x) ->
      let x' = normalize_eq_symm x in
      if x == x' then p else mk_lambda s x'
    | _ -> p


let normalize_clause = List.map normalize_eq_symm

let register_clause_id cl id =
  HCl.add clauses_ids cl id;
  Hashtbl.add ids_clauses id cl

(* let register_clause_id cl id = *)
(*   List.iter (fun cl -> register_clause_id cl id) *)
(*     (clause_mod_eqsymm cl) *)


let new_clause_id ?(reuse=true) cl =
 let cl = normalize_clause cl in
  try
    if not reuse then raise Not_found;
    OldCl (HCl.find clauses_ids cl)
  with Not_found ->
    (* eprintf "new clause : [%a]@." (fun fmt -> List.iter (fprintf fmt "%a, " Ast.print_term)) cl; *)
    incr cl_cpt;
    let id = !cl_cpt in
    register_clause_id cl id;
    NewCl id


let mk_clause ?(reuse=true) rule cl args =
  match new_clause_id ~reuse cl with
  | NewCl id ->
    fprintf fmt "%d:(%s %a%a)@." id (get_rule rule) print_clause cl
      (fun fmt -> List.iter (fprintf fmt " %d")) args;
    id
  | OldCl id -> id


let mk_clause_cl = mk_clause


let mk_input name formula =
  let cl = [formula] in
  match new_clause_id cl with
   | NewCl id ->
     register_clause_id cl id;
     HS.add inputs name id;
     fprintf fmt "%d:(input (%a))@." id print_term formula
   | OldCl _ -> ()


let mk_admit_preproc name formula =
  let cl = [formula] in
  match new_clause_id cl with
   | NewCl id ->
     register_clause_id cl id;
     HS.add inputs name id;
     fprintf fmt "%d:(hole (%a))@." id print_term formula
   | OldCl _ -> ()


let register_prop_abstr vt formula = HT.add propvars vt formula


let get_clause_id cl = HCl.find clauses_ids cl


let get_input_id h = HS.find inputs h


let register_decl name formula =
  let cl = [formula] in
  match new_clause_id cl with
  | NewCl id | OldCl id -> HS.add inputs name id


let register_decl_id name id = HS.add inputs name id


let register_alias name_index t = HS.add alias_tbl name_index t


(* let register_termalias a t = HT.add termalias_tbl a t *)


let clear () =
  HCl.clear clauses_ids;
  Hashtbl.clear ids_clauses;
  HT.clear propvars;
  HT.clear sharp_tbl;
  Hashtbl.clear inputs;
  HS.clear alias_tbl;
  (* HT.clear termalias_tbl; *)
  cl_cpt := 0;
  cpt := 0
  
