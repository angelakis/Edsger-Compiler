open Core.Std
open Ast
open Format
open Identifier
open Types
open Symbol
open NiceDebug

exception Terminate of string

(* TODO: optionally could be refined, *)
let rec eval_const_int = function
	| E_int x       -> int_of_string x
	(*TODO:Tranform the parsing of int to Edsger Specific *)
	| E_plus (x,y)  -> ((eval_const_int x)+(eval_const_int y))
	| E_minus (x,y) -> ((eval_const_int x)-(eval_const_int y))
	| E_div (x,y)   -> ((eval_const_int x)/(eval_const_int y))
	| E_mult (x,y)  -> ((eval_const_int x)*(eval_const_int y))
	| E_mod (x,y)   -> ((eval_const_int x)mod(eval_const_int y))
	| _ -> raise (Terminate "Not Constant Int Expression")

let rec eval_expr = function
	| E_function_call (x,l) -> 
		(* Doesn't check arguments yet, improve it to do so*)
		begin 
			let param_list =
				match l with 
				| Some lst -> lst
				| None -> []
			in 
			let overloaded_name = x ^ "_" ^ (string_of_int (List.length param_list)) in
			lookup_result_type overloaded_name
		end
    | E_id str -> printf "will lookup for %s\n" str;lookup_result_type str
    | E_int _ -> TYPE_int 0
    | E_bool _ -> TYPE_bool 0
    | E_char _ -> TYPE_char 0
    | E_double _ -> TYPE_double 0
    | E_string x -> TYPE_array (TYPE_char 0, String.length x)
    | E_null -> TYPE_null 
    | E_plus (x,y) -> check_eval_ar_op (x,y)
    | E_minus (x,y) -> check_eval_ar_op (x,y)
    | E_div (x,y) -> check_eval_ar_op (x,y)
    | E_mult (x,y) -> check_eval_ar_op (x,y)
    | E_mod (x,y) -> check_eval_ar_op (x,y)
	(* Logical Operator*)
    | E_and (x,y) | E_or (x,y) -> 
		if (not (check_binary_logical_operator x y))
			then raise (Terminate "operands of and/or should be booleans\n")
			else TYPE_bool 0
	| E_lteq (x,y) | E_gteq (x,y) | E_lt  (x,y) | E_gt  (x,y) 
	| E_neq (x,y) | E_eq  (x,y) -> 
		let _ = check_eval_ar_op (x,y) in (); TYPE_bool 0
    | E_comma (x,y) -> (ignore (eval_expr x); eval_expr y)
    | E_assign (x,y) -> (ignore (eval_expr x); eval_expr y) (* LVALUE CHECK! *)
    | E_mul_assign (x,y) ->  if equalType (eval_expr y) (eval_expr x) then
                                eval_expr y
                            else
                                raise (Terminate "Non-matching types assignment")
    | E_div_assign (x,y) ->  if equalType (eval_expr y) (eval_expr x) then
                                eval_expr y
                            else
                                raise (Terminate "Non-matching types assignment")
    | E_mod_assign (x,y) ->  if equalType (eval_expr y) (eval_expr x) then
                                eval_expr y
                            else
                                raise (Terminate "Non-matching types assignment")
    | E_plu_assign (x,y) ->  if equalType (eval_expr y) (eval_expr x) then
                                eval_expr y
                            else
                                raise (Terminate "Non-matching types assignment")
    | E_min_assign (x,y) -> if equalType (eval_expr y) (eval_expr x) then
                                eval_expr y
                            else
                                raise (Terminate "Non-matching types assignment")
    | E_negate x -> (ignore (eval_expr x); TYPE_bool 0)
    | E_uplus x -> eval_expr x
    | E_uminus x -> eval_expr x
    | E_addr x ->  addr_of_point (eval_expr x)
    | E_deref x -> deref_expr (eval_expr x)
    | E_incr_bef x -> (ignore (eval_expr x); TYPE_int 0)
    | E_decr_bef x -> (ignore (eval_expr x); TYPE_int 0)
    | E_incr_aft x -> (ignore (eval_expr x); TYPE_int 0)
    | E_decr_aft x -> (ignore (eval_expr x); TYPE_int 0) (*we need an lvalue check function*)
    | E_array_access (x,y) -> if (equalType (eval_expr y) (TYPE_int 0)) then
                                  eval_expr x 
                              else
                                  raise (Terminate "Array index not int")
    | E_delete x -> if is_pointer (eval_expr x) then
                        eval_expr x
                    else
                        raise (Terminate "Can't delete non-point")
    | E_new (x, None) -> addr_of_point (map_to_symbol_table_type x)
    | E_new (x, Some y) -> if equalType (eval_expr y) (TYPE_int 0) then
                                addr_of_point (map_to_symbol_table_type x)
                           else
                                raise (Terminate "Non int array size")
    | E_cast (x, y) -> (ignore (eval_expr y); map_to_symbol_table_type x) 
    | E_ternary_op (x, y, z) ->
		if (equalType (eval_expr x) (TYPE_bool 0)) 
		&& (equalType (eval_expr y) (eval_expr z)) then
			eval_expr z
		else
			raise (Terminate "Wrong types ternary")

and check_eval_ar_op = function
    | (x,y) ->
		let x_eval = eval_expr x in 
		let y_eval = eval_expr y in
			  if (x_eval) <> (y_eval) then
                    raise (Terminate "Addition arguments don't match")
               else 
                    x_eval 

and check_eval_of_type x y ~wanted_type =
	(let res1 = check_eval_ar_op (x,y) in
	equalType res1 wanted_type)

and check_binary_logical_operator x y =
	check_eval_of_type x y ~wanted_type:(TYPE_bool 0)

and check ast =
	match ast with
	| None      -> raise (Terminate "AST is empty")
	| Some tree -> (
		initSymbolTable 256;
		openScope();
		check_all_decls tree;
		(* check for main -- TODO: check there is an implementation too *)
		if (lookup_result_type "main_0" <> TYPE_void) 
			then raise (Terminate "main should return void");
		printSymbolTable())

and check_all_decls decls =
	List.iter decls check_a_declaration;

and check_a_declaration  = 
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
		endFunctionHeader brand_new_fun symtbl_ret_type
	in
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
			(* This Folding Returns whether return statement is guaranteed or not *)
			let guaranteed_return = 
				List.fold fun_stmts ~init:false ~f:(check_a_statement id)
			in
			if (not guaranteed_return) && (not (equalType TYPE_void (lookup_result_type id))) then
				raise (Terminate "return value is not guaranteed in a non-void function");
			closeScope ();
		end);


(* check_a_statement function takes three arguments *)
(* 1st: function in which this statement executes *)
(* 2nd: this argument states the current guarantee of return statement *)
(* 3rd: this argument is the statement for semantic analysis *)

and check_a_statement func_id status =  
	(function 
	| S_None -> status
	| S_expr expr -> let _ = eval_expr expr in status
	| S_braces many_stmts -> 
		begin 
			printf "New block\n";
			(* TODO: Double check that this is not necessery! *)
			(* openScope(); This Is probably not necessery *)
			List.fold many_stmts ~init:status ~f:(check_a_statement func_id)
			(* closeScope()  *)
		end
	| S_if (bool_expr,if_stmt,el_stmt) ->
		begin
			printf "new if statement\n"; 
			if (equalType (eval_expr bool_expr) (TYPE_bool 0)) then
				begin
					let return_status_of_if = check_a_statement func_id status if_stmt in
					let return_status_of_else = 
						(match el_stmt with
						 | Some e -> printf "else stmt\n"; check_a_statement func_id status e
						 | None -> false)
					 in 
					 status || (return_status_of_else && return_status_of_if)
				end
			else raise (Terminate "if statement lacks boolean check")
		end
	| S_for (label,expr1,expr2,expr3,stmt) ->
		begin 
			printf "new for statement\n";

			(* manage label existance *)
			let labl = (match label with
			| Some l -> (newLabel (id_make l) true)
			| None -> (let e =  no_entry (id_make "___trash") in e)) in 
			let for_exps = (function
			| Some exp -> 
				eval_expr exp
			| None -> TYPE_bool 0) in 
			(* execute the analysis  of the first expression *)
			let _ = for_exps expr1 in (); 
			(* do the same for the second, while checking for being boolean*)
			if not ( equalType (for_exps expr2) (TYPE_bool 0))then
				raise (Terminate "guard in for statement should be boolean or empty\n");
			(* third expression *)
			let _ = for_exps expr3 in 
			let _ = check_a_statement func_id status stmt in 
			(* disable label acceptance *)
			(match label with
			| Some l -> endLabelScope labl
			| None -> ());
			status 
			(* Do not change return-existance status, since for loops may or may not*)
			(* execute *)
		end
	| S_continue label | S_break label -> 
		begin 
			let labl = (match label with
			| Some l -> l
			| None -> "") in
			if labl <> "" then begin
				let lbl_entry = lookupEntry (id_make labl) LOOKUP_CURRENT_SCOPE true in
				match lbl_entry.entry_info with
				| ENTRY_label v -> 
					if (not !v) then raise (Terminate "This label does not correspond to a valid loop")
				| ENTRY_none ->  
					();
				| _ -> raise (Terminate "BAD ENTRY TYPE MISTER DEVELOPER")
			end; 
			status
		end
	| S_return r -> 
			(match r with
			| Some expr ->
				if not (equalType (eval_expr expr) (lookup_result_type func_id) ) then 
					raise (Terminate "return type is not correct") 
			| None -> 
				if not (equalType TYPE_void (lookup_result_type func_id) ) then
					raise (Terminate "return type is not correct")
			); 
			true (* found a RETURN ! so return true*)
	)	

