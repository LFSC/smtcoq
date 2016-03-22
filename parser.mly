%{
  (* Parser: Grammar Specification for Parsing S-expressions *)

open Ast
open Lexing
open Format
open Builtin

let parse_failure what =
  let pos = Parsing.symbol_start_pos () in
  let msg =
    Printf.sprintf "Sexplib.Parser: failed to parse line %d char %d: %s"
      pos.pos_lnum (pos.pos_cnum - pos.pos_bol) what in
  failwith msg

let scope = ref []

let renamings = Hashtbl.create 21

let register_rename = Hashtbl.add renamings

let remove_rename = Hashtbl.remove renamings



%}

%token <string> STRING
%token <Big_int.big_int> INT
%token LPAREN RPAREN EOF HASH_SEMI
%token LAMBDA PI BIGLAMBDA COLON
%token CHECK DEFINE DECLARE
%token MPQ MPZ HOLE TYPE KIND
%token SC PROGRAM AT

%start proof
%type <Ast.proof> proof

%start proof_print
%type <unit> proof_print

%start proof_ignore
%type <unit> proof_ignore

%start one_command
%type <Ast.command> one_command

%start sexp
%type <Type.t> sexp

%start sexp_opt
%type <Type.t option> sexp_opt

%start sexps
%type <Type.t list> sexps

%start rev_sexps
%type <Type.t list> rev_sexps

%%
sexp:
| sexp_comments sexp_but_no_comment { $2 }
| sexp_but_no_comment { $1 }

sexp_but_no_comment
  : STRING { Type.Atom $1 }
  | LPAREN RPAREN { Type.List [] }
  | LPAREN rev_sexps_aux RPAREN { Type.List (List.rev $2) }
  | error { parse_failure "sexp" }

sexp_comment
  : HASH_SEMI sexp_but_no_comment { () }
  | HASH_SEMI sexp_comments sexp_but_no_comment { () }

sexp_comments
  : sexp_comment { () }
  | sexp_comments sexp_comment { () }

sexp_opt
  : sexp_but_no_comment { Some $1 }
  | sexp_comments sexp_but_no_comment { Some $2 }
  | EOF { None }
  | sexp_comments EOF { None }

rev_sexps_aux
  : sexp_but_no_comment { [$1] }
  | sexp_comment { [] }
  | rev_sexps_aux sexp_but_no_comment { $2 :: $1 }
  | rev_sexps_aux sexp_comment { $1 }

rev_sexps
  : rev_sexps_aux EOF { $1 }
  | EOF { [] }

sexps
  : rev_sexps_aux EOF { List.rev $1 }
  | EOF { [] }
;

ignore_sexp_list :
  | { }
  | sexp ignore_sexp_list { }
;

term_list:
  | term { [$1]}
  | term term_list { $1 :: $2 }
;

binding:
  | STRING term {
    let n = String.concat "." (List.rev ($1 :: !scope)) in
    let s = mk_symbol n $2 in
    register_symbol s;
    register_rename $1 n;
    s, $1
  }
;

untyped_sym:
  | STRING {
    let s = mk_symbol $1 (mk_hole_hole ()) in
    register_symbol s;
    s
  }
;

let_binding:
  | STRING term {
    let t = $2 in
    let s = mk_symbol $1 t.ttype in
    register_symbol s;
    add_definition s t;
    s
  }
;

/*
ignore_string_or_hole:
  | STRING { }
  | HOLE { }
;
*/

term:
  | TYPE { lfsc_type }
  | KIND { kind }
  | MPQ { mpq }
  | MPZ { mpz }
  | INT { mk_mpz $1 }
  | STRING
    {
      let n = try Hashtbl.find renamings $1 with Not_found -> $1 in
      mk_const n
    }
  | HOLE { mk_hole_hole () }
  | LPAREN AT let_binding term RPAREN { remove_definition $3; $4 }
  | LPAREN term term_list RPAREN { mk_app $2 $3 }
  | LPAREN LAMBDA untyped_sym term RPAREN
    { let s = $3  in
      let t = $4 in
      let r = mk_lambda s t in
      remove_symbol s;
      r
    }
  | LPAREN LAMBDA HOLE term RPAREN
    { let s = mk_symbol_hole (mk_hole_hole ()) in
      let t = $4 in
      mk_lambda s t }
  | LPAREN BIGLAMBDA binding term RPAREN
    { let s, old = $3 in
      let t = $4 in
      let r = mk_lambda s t in
      remove_symbol s;
      remove_rename old;
      r
    }
  | LPAREN BIGLAMBDA HOLE term term RPAREN
    { let t = $5 in
      let s = mk_symbol_hole $4 in
      mk_lambda s t }
  | LPAREN PI binding term RPAREN
    { let s, old = $3 in
      let t = $4 in
      let r = mk_pi s t in
      remove_symbol s;
      remove_rename old;
      r
    }
  | LPAREN PI HOLE term term RPAREN
    { let s = mk_symbol_hole $4 in
      let t = $5 in
      mk_pi s t }
  | LPAREN PI STRING /* ignore_string_or_hole */
    LPAREN SC LPAREN STRING term_list RPAREN term RPAREN term RPAREN
    {
      add_sc $7 $8 $10 $12
    }
  | LPAREN COLON term term RPAREN
    { mk_ascr $3 $4 }
;

declare:
  | DECLARE STRING { scope := [$2]; $2 }
;

define:
  | DEFINE STRING { scope := [$2]; $2 }
;



command:
  | LPAREN CHECK term RPAREN {
    mk_check $3;
    Check $3 }
  | LPAREN define term RPAREN {
    mk_define $2 $3;
    scope := [];
    Define ($2, $3) }
  | LPAREN declare term RPAREN {
    mk_declare $2 $3;
    scope := [];
    Declare ($2, $3)
  }
;

command_print:
  | command { printf "@[<hov 1>%a@]@\n@." print_command $1 }
  | LPAREN PROGRAM STRING ignore_sexp_list RPAREN
    { printf "Ignored program %s\n@." $3 }
;

command_ignore:
  | command { () }
  | LPAREN PROGRAM STRING ignore_sexp_list RPAREN { () }
;


one_command:
  | command EOF { $1 }
;

command_list:
  | { [] }
  | command command_list { $1 :: $2 }
;

command_print_list:
  | { }
  | command_print command_print_list { }
;

command_ignore_list:
  | { }
  | command_ignore command_ignore_list { }
;

proof:
  | command_list EOF { $1 }
;

proof_print:
  | command_print_list EOF { }
;

proof_ignore:
  | command_ignore_list EOF { }
;

