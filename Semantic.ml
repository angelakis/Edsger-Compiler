open Core.Std
open Ast
open Format
open Identifier
open Types
open Symbol

exception Terminate of string
exception NoMainFunction

let show_offsets = true

let rec pretty_typ ppf typ =
  let pretty_pointer n = 
	let rec aux str = function
	| 0 -> str
	| n -> aux (str ^ "*") (n-1)
	in aux "" n
  in
  match typ with
  | TYPE_none ->
      fprintf ppf "<undefined>"
  | TYPE_int n ->
      fprintf ppf "int %s" (pretty_pointer n)
  | TYPE_char n->
      fprintf ppf "char %s" (pretty_pointer n)
  | TYPE_bool n->
      fprintf ppf "bool %s" (pretty_pointer n)
  | TYPE_double n ->
      fprintf ppf "double %s"  (pretty_pointer n)
  | TYPE_array (et, sz) ->
      pretty_typ ppf et;
      if sz > 0 then
        fprintf ppf " [%d]" sz
      else
        fprintf ppf " []"
  | TYPE_proc ->
      fprintf ppf "proc"

let pretty_mode ppf mode =
  match mode with
  | PASS_BY_REFERENCE ->
      fprintf ppf "reference "
  | _ ->
      ()

let printSymbolTable () =
  let rec walk ppf scp =
    if scp.sco_nesting <> 0 then begin
      fprintf ppf "scope: ";
      let entry ppf e =
        fprintf ppf "%a" pretty_id e.entry_id;
        match e.entry_info with
        | ENTRY_none ->
            fprintf ppf "<none>"
        | ENTRY_variable inf ->
            if show_offsets then
              fprintf ppf "[%d]" inf.variable_offset
        | ENTRY_function inf ->
            let param ppf e =
              match e.entry_info with
                | ENTRY_parameter inf ->
                   fprintf ppf "%a%a : %a"
                      pretty_mode inf.parameter_mode
                      pretty_id e.entry_id
                      pretty_typ inf.parameter_type
                | _ ->
                    fprintf ppf "<invalid>" in
            let rec params ppf ps =
              match ps with
              | [p] ->
                  fprintf ppf "%a" param p
              | p :: ps ->
                  fprintf ppf "%a; %a" param p params ps;
              | [] ->
                  () in
            fprintf ppf "(%a) : %a"
              params inf.function_paramlist
              pretty_typ inf.function_result
        | ENTRY_parameter inf ->
            if show_offsets then
              fprintf ppf "[%d]" inf.parameter_offset
        | ENTRY_temporary inf ->
            if show_offsets then
              fprintf ppf "[%d]" inf.temporary_offset in
      let rec entries ppf es =
        match es with
          | [e] ->
              fprintf ppf "%a" entry e
          | e :: es ->
              fprintf ppf "%a, %a" entry e entries es;
          | [] ->
              () in
      match scp.sco_parent with
      | Some scpar ->
          fprintf ppf "%a\n%a"
            entries scp.sco_entries
            walk scpar
      | None ->
          fprintf ppf "<impossible>\n"
    end in
  let scope ppf scp =
    if scp.sco_nesting == 0 then
      fprintf ppf "no scope\n"
    else
      walk ppf scp in
  printf "%a----------------------------------------\n"
    scope !currentScope

(* +------------------------------------------------------------------------------+ *)
(* | Assertion of Return Types Through Lookup Tables                              | *)
(* +------------------------------------------------------------------------------+ *)


(* TODO: needs refinement, for now check if int *)
let rec eval_const_int = function
	| E_int x -> int_of_string x 
	(*TODO:Tranform the parsing of int to Edsger Specific *)
	| E_plus (x,y) ->((eval_const_int x)+(eval_const_int y))
	| E_minus (x,y) -> ((eval_const_int x)-(eval_const_int y))
	| E_div (x,y)  -> ((eval_const_int x)/(eval_const_int y))
	| E_mult (x,y) ->((eval_const_int x)*(eval_const_int y))
	| E_mod (x,y) -> ((eval_const_int x)mod(eval_const_int y)) 
	| _ -> raise (Terminate "Not Constant Int Expression")

(* Doesn't utilize number of pointers yet, have that in mind *) 
(* to improve data-types of hash table *) 
let map_to_symbol_table_type = function
	| Ty_int n -> TYPE_int n
	| Ty_char n -> TYPE_char n
	| Ty_bool n -> TYPE_bool n
	| Ty_double n -> TYPE_double n
	| _ -> raise (Terminate "Bad Type")

let def_func_head typ id params ~forward=
	let symtbl_ret_type = map_to_symbol_table_type typ in
	let brand_new_fun = newFunction (id_make id) true in
	openScope ();
	(match params with
	| Some param_list -> 
		(List.iter param_list
		(function 
			| P_byval (typ, id) -> let dmy = newParameter (id_make id) (map_to_symbol_table_type typ)  PASS_BY_VALUE brand_new_fun  true in ignore dmy;() 
			| P_byref (typ, id) -> let dmy = newParameter (id_make id)  (map_to_symbol_table_type typ) PASS_BY_REFERENCE brand_new_fun  true  in ignore dmy; ()
		))
	| None -> ());
	if forward then forwardFunction brand_new_fun;
	endFunctionHeader brand_new_fun symtbl_ret_type;;

let rec check ast =
	match ast with
	| None      -> raise (Terminate "AST is empty")
	| Some tree -> (
		initSymbolTable 256;
		openScope();
		check_all_decls tree;
		printSymbolTable())

and check_all_decls decls =
	List.iter decls check_a_declaration 

and check_a_declaration  = 
	(function
    (***********************************************)
    (*** VARIABLES DECLARATION                   ***)
    (***********************************************)

	| D_var_decl (typ,defines) -> 
		let sym_tbl_type = map_to_symbol_table_type typ in
		let _ = printf "- var definition\n" in 
		List.iter 
			defines (* Check and Register Definitions*) 
			(function 
			| (id,Some expr) -> 
				let dmy = 
					newVariable (id_make id)
						(TYPE_array (sym_tbl_type,eval_const_int expr))
						true 
				in ignore dmy; ()
			| (id,None) -> 
				let dmy = newVariable (id_make id)
					sym_tbl_type true 
				in ignore dmy; ()
			) 

    (***********************************************)
    (*** FUNCTION DECLARATION                    ***)
    (***********************************************)

	| D_func_decl (typ,id,params) -> 
		begin 
			printf "- fun decl %s\n" id;
			def_func_head typ id params ~forward:true;
			closeScope ();
		end
    (***********************************************)
    (*** FUNCTION DEFINITION                     ***)
    (***********************************************)

	| D_func_def (typ,id,params,fun_decls,fun_stmts) -> 	
		begin
			printf "- fun def %s\n" id;
			def_func_head typ id params ~forward:false;
			(match fun_decls with
				| Some declerations -> check_all_decls declerations
				| None -> ()
			);
			List.iter fun_stmts check_a_statement;
			closeScope ();
		end)

and check_a_statement stmt = ();
	
	

(* Params: Accumulated-Declarations, New Declaration *)
(* and check_decls acc_decls new_decl = *) 
(* 	match new_decl with *)
(* 	| D_var_decl (defed_type,vars) -> *)
(* 		List.iter (*Function:Add Variable of type defed_type*) vars *)
(* 	| D_func_decl (ret_type,fun_id,params) -> *)
(* 		let params =List.fold_left  ~f:(*Function:Add Fun Decl*) *) 
(* 									~init:[] *)

(****************************)
(* and check_program decls = *)
(* 	initSymbolTable 256; *)
(* 	printSymbolTable (); *)
(* 	openScope(); *)
(* 	printSymbolTable (); *)
(* 	let i1 = newVariable (id_make "i1") TYPE_int true in *)
(* 	let i2 = newVariable (id_make "i2") TYPE_int true in *)
(* 	ignore i1; ignore i2; *)
(* 	printSymbolTable (); *)
(* 	let p = newFunction (id_make "pr") true in *)
(* 	openScope (); *)
(* 	printSymbolTable (); *)
(* 	let p1 = newParameter (id_make "p1") TYPE_int  PASS_BY_VALUE p true in *)
(* 	let p2 = newParameter (id_make "p2") TYPE_int  PASS_BY_VALUE p true in *)
(* 	let p3 = newParameter (id_make "p3") TYPE_char PASS_BY_REFERENCE p true in *)
(* 	endFunctionHeader p TYPE_proc; *)
(* 	ignore p1; ignore p2; ignore p3; *)
(* 	printSymbolTable (); *)
(* 	let b1 = newVariable (id_make "b1") TYPE_bool true in *)
(* 	ignore b1; *)
(* 	let i1 = newVariable (id_make "i1") TYPE_int true in *)
(* 	ignore i1; *)
(* 	printSymbolTable (); *)
(* 	let i2 = lookupEntry (id_make "i2") LOOKUP_ALL_SCOPES true in *)
(* 	let i1 = lookupEntry (id_make "i1") LOOKUP_ALL_SCOPES true in *)
(* 	ignore i2; ignore i1; *)
(* 	let t1 = newTemporary TYPE_int in *)
(* 	let t2 = newTemporary TYPE_char in *)
(* 	ignore t1; ignore t2; *)
(* 	printSymbolTable (); *)
(* 	closeScope (); *)
(* 	printSymbolTable (); *)
(* 	let p = newFunction (id_make "f") true in *)
(* 	openScope (); *)
(* 	printSymbolTable (); *)
(* 	let x = newParameter (id_make "x") TYPE_int PASS_BY_VALUE p true in *)
(* 	let y = newParameter (id_make "y") TYPE_char PASS_BY_REFERENCE p true in *)
(* 	endFunctionHeader p TYPE_int; *)
(* 	ignore x; ignore y; *)
(* 	printSymbolTable (); *)
(* 	closeScope (); *)
(* 	printSymbolTable (); *)
(* 	let t1 = newTemporary TYPE_int in *)
(* 	let t2 = newTemporary TYPE_int in *)
(* 	ignore t1; ignore t2; *)
(* 	printSymbolTable (); *)
(* 	closeScope (); *)
(* 	printSymbolTable () *)

