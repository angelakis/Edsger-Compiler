open Ast
exception Terminate of string

type typ = 
	  TYPE_none
	| TYPE_int    of int
	| TYPE_char   of int
	| TYPE_bool   of int
	| TYPE_double of int
	| TYPE_array  of typ * int
	| TYPE_void
	| TYPE_null

let rec sizeOfType t =
   match t with
	(*-- Primitive Type Sizes  --*)
   | TYPE_int n when n=0	 -> 2
   | TYPE_char n when n=0    -> 1
   | TYPE_bool n when n=0    -> 1
   | TYPE_double n when n=0  -> 10
	(*-- Pointers Cost 2 Bytes --*)
   | TYPE_int _ | TYPE_char _ | TYPE_bool _ | TYPE_double _ -> 2
	(*-- Arrays Cost According to their size --*)
   | TYPE_array (et, sz) 	-> sz * sizeOfType et
   | _						 -> 0

let rec equalType t1 t2 =
   match t1, t2 with
   | TYPE_array (et1, sz1), TYPE_array (et2, sz2) -> equalType et1 et2
   | et1, TYPE_null when et1 <> TYPE_null         -> equalType t2 t1
   | TYPE_null, TYPE_null                         -> true
   | TYPE_null, TYPE_int n when n > 0             -> true
   | TYPE_null, TYPE_bool n when n > 0            -> true
   | TYPE_null, TYPE_char n when n > 0            -> true
   | TYPE_null, TYPE_double n when n > 0          -> true
   | _                                            -> t1 = t2

let map_to_symbol_table_type = function
	| Ty_int n -> TYPE_int n
	| Ty_char n -> TYPE_char n
	| Ty_bool n -> TYPE_bool n
	| Ty_double n -> TYPE_double n
	| Ty_void -> TYPE_void
	(* | _ -> raise (Terminate "Bad Type") *)

let is_pointer = function
    | TYPE_int x when x>0           -> true
    | TYPE_char x when x>0          -> true
    | TYPE_bool x when x>0          -> true
    | TYPE_double x when x>0        -> true
    | TYPE_array (x,y)              -> true
    | _                             -> false

let rec addr_of_point = function
    | TYPE_int x        -> TYPE_int (x+1)
    | TYPE_char x       -> TYPE_char (x+1)
    | TYPE_bool x       -> TYPE_bool (x+1)
    | TYPE_double x     -> TYPE_double (x+1)
    | TYPE_array (x,y)  -> TYPE_array (addr_of_point x,y) (* ??? *)
    | TYPE_null         -> TYPE_null
    | _                 -> raise (Terminate "bad addr type")

let rec deref_expr = function
    | TYPE_int x when x>0           -> TYPE_int (x-1)
    | TYPE_char x when x>0          -> TYPE_char (x-1)
    | TYPE_bool x when x>0          -> TYPE_bool (x-1)
    | TYPE_double x when x>0        -> TYPE_double (x-1)
    | TYPE_array (x,y)              -> TYPE_array (deref_expr x,y)
    | _                             -> raise (Terminate "deref non-pointer")

