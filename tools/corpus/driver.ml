(* Timbda-0 differential harness - the extracted-evaluator corner.

   This driver is the *independent* reader of the corpus (tests/corpus/*.texpr):
   it parses the corpus surface syntax itself (no generated code, no Coq), builds
   the AST of the OCaml code produced by `Extraction` from the kernel
   (tools/extract/extract.v -> timbda_eval.ml), runs `Timbda_eval.norm` /
   `Timbda_eval.head_redex` on it, and compares against the corpus' expected
   normal form and expected head row.

   Why an independent reader matters: the Coq corner (tools/corpus/corpus.py
   --emit-coq) feeds the same corpus into Coq's evaluator through a generated
   file.  Here the corpus reaches a *different* implementation (extracted OCaml)
   through a *different* parser, so an extraction or evaluator regression shows up
   as a case failure rather than as a shared-blind-spot agreement.

   Exit status: 0 iff every case matched.  flake.nix runs this at build time
   (packages.timbda-extracted-eval) and keeps the report as build evidence. *)

module E = Timbda_eval

(* ---------- corpus AST (deliberately separate from the extracted one) ---------- *)

type cty = Cy_unit | Cy_bool | Cy_int | Cy_arr of cty * cty | Cy_any

type cval =
  | Cv_unit | Cv_true | Cv_false | Cv_int of int | Cv_prim of string
  | Cv_tup of cval list | Cv_lam of cty * cexpr | Cv_delay of cexpr | Cv_var of int
and cexpr =
  | Ce_ret of cval | Ce_glob of int | Ce_app of cexpr * cexpr | Ce_tup of cexpr list
  | Ce_seq of cexpr * cexpr | Ce_unify of cexpr * cexpr | Ce_choice of cexpr * cexpr
  | Ce_fail | Ce_block of (cty * cval option) list * cexpr
  | Ce_iter of string * cexpr * cexpr

type head_want = H_none | H_row of E.ruleID

type cspec = {
  c_name : string;
  mutable c_fuel : int;
  mutable c_head : head_want;
  mutable c_expr : cexpr;
  mutable c_norm : cexpr;
  mutable c_why : string;
  mutable c_cands : cexpr list option;   (* Some bag = this case also checks cand_bag *)
  mutable c_cands_why : string;
  mutable c_has_head : bool;
  mutable c_has_expr : bool;
  mutable c_has_norm : bool;
}

exception Corpus_error of string

let fail msg = raise (Corpus_error msg)

(* ---------- tables mirroring coq/Syntax.v and coq/Eval.v ---------- *)

let prim_table = [
  ("padd", E.PAdd); ("psub", E.PSub); ("pmul", E.PMul); ("pdiv", E.PDiv);
  ("pneg", E.PNeg); ("ppls", E.PPls); ("pgt", E.PGt); ("plt", E.PLt);
  ("pgeq", E.PGEq); ("pleq", E.PLEq); ("pneq", E.PNEq);
  ("pisint", E.PIsInt); ("pisbool", E.PIsBool); ("pisunit", E.PIsUnit);
  ("pcons", E.PCons); ("pcons2", E.PCons2); ("pdotdot", E.PDotDot);
  ("parrlen", E.PArrLen);
]

let comb_table = [ ("iall", E.IAll); ("iif", E.IIf); ("ifor", E.IFor) ]

let row_table = [
  ("r_seq", E.R_Seq); ("r_norm1", E.R_Norm1); ("r_norm2", E.R_Norm2);
  ("r_norm3", E.R_Norm3); ("r_norm4", E.R_Norm4); ("r_norm5", E.R_Norm5);
  ("r_eqk1", E.R_EqK1); ("r_eqk2", E.R_EqK2); ("r_eqtup1", E.R_EqTup1);
  ("r_eqtup2", E.R_EqTup2); ("r_eqfail", E.R_EqFail); ("r_betal", E.R_BetaL);
  ("r_betat", E.R_BetaT); ("r_betat0", E.R_BetaT0); ("r_prim", E.R_Prim);
  ("r_primfail", E.R_PrimFail); ("r_subst", E.R_Subst); ("r_gc1", E.R_Gc1);
  ("r_promotel", E.R_PromoteL); ("r_promoter", E.R_PromoteR);
  ("r_iterfail", E.R_IterFail); ("r_iterchoice", E.R_IterChoice);
  ("r_iterif", E.R_IterIf); ("r_iterall", E.R_IterAll);
  ("r_iterfor", E.R_IterFor); ("r_hpalpha", E.R_HpAlpha);
  ("r_lamalpha", E.R_LamAlpha);
]

let lookup table key what =
  match List.assoc_opt key table with
  | Some v -> v
  | None -> fail (what ^ ": unknown name " ^ key)

(* ---------- surface-syntax reader (lexer + recursive descent) ---------- *)

let is_space c = c = ' ' || c = '\t' || c = '\r'
let is_delim c = is_space c || c = '(' || c = ')'

let tokenize s =
  let n = String.length s in
  let rec skip i = if i < n && is_space s.[i] then skip (i + 1) else i in
  let rec atom_len i = if i < n && not (is_delim s.[i]) then atom_len (i + 1) else i in
  let rec go i acc =
    let i = skip i in
    if i >= n then List.rev acc else
    match s.[i] with
    | '(' -> go (i + 1) ("(" :: acc)
    | ')' -> go (i + 1) (")" :: acc)
    | _ -> let j = atom_len i in go j (String.sub s i (j - i) :: acc)
  in
  go 0 []

let is_number tok =
  let t = if String.length tok > 0 && tok.[0] = '-' then String.sub tok 1 (String.length tok - 1) else tok in
  String.length t > 0 && t.[0] >= '0' && t.[0] <= '9'
  && let ok = ref true in
  String.iter (fun c -> if c < '0' || c > '9' then ok := false) t; !ok

(* Parse one form (`read_form`), or a whitespace-separated run of forms
   (`read_forms ~multi`, the `cands` field).  `ty`, `value`, `expr` and `slot` are
   mutually recursive, like the corpus grammar they read. *)
let read_forms ?(multi = false) ctx line =
  let toks = Array.of_list (tokenize line) in
  let n = Array.length toks in
  let pos = ref 0 in
  let peek () = if !pos < n then Some toks.(!pos) else None in
  let take () =
    match peek () with
    | Some t -> incr pos; t
    | None -> fail (ctx ^ ": form ends too early")
  in
  let expect tok =
    match peek () with
    | Some t when t = tok -> incr pos
    | other -> fail (ctx ^ ": expected \"" ^ tok ^ "\", got " ^
                       (match other with Some t -> "\"" ^ t ^ "\"" | None -> "end of form"))
  in
  let atom () =
    let t = take () in
    if t = "(" || t = ")" then fail (ctx ^ ": expected an atom, got \"" ^ t ^ "\"") else t
  in
  (* Read forms until the closing ")", consume it, return them in source order. *)
  let many reader =
    let rec go acc =
      match peek () with
      | Some ")" -> incr pos; List.rev acc
      | Some _ -> let x = reader () in go (x :: acc)
      | None -> fail (ctx ^ ": form ends too early")
    in go []
  in
  let rec ty () =
    let name = atom () in
    match name with
    | "tunit" -> Cy_unit | "tbool" -> Cy_bool | "tint" -> Cy_int | "tany" -> Cy_any
    | _ -> fail (ctx ^ ": unknown type " ^ name)
  and value () =
    if peek () <> Some "(" then begin
      let tok = take () in
      if tok = "unit" then Cv_unit
      else if tok = "true" then Cv_true
      else if tok = "false" then Cv_false
      else if is_number tok then Cv_int (int_of_string tok)
      else fail (ctx ^ ": unexpected " ^ tok ^ " in value position")
    end else begin
      expect "(";
      let head = atom () in
      if head = "primv" then begin
        let name = atom () in ignore (lookup prim_table name "prim"); expect ")"; Cv_prim name
      end else if head = "tupv" then Cv_tup (many value)
      else if head = "lam" then begin
        let t = ty () in let body = expr () in expect ")"; Cv_lam (t, body)
      end else if head = "delay" then begin
        let body = expr () in expect ")"; Cv_delay body
      end else if head = "var" then begin
        let k = int_of_string (atom ()) in expect ")"; Cv_var k
      end else fail (ctx ^ ": unknown value form " ^ head)
    end
  and slot () =
    expect "(";
    let t = ty () in
    if peek () = Some ")" then (expect ")"; (t, None))
    else begin let v = value () in expect ")"; (t, Some v) end
  and expr () =
    if peek () <> Some "(" then begin
      let tok = take () in
      if tok = "fail" then Ce_fail
      else fail (ctx ^ ": unexpected " ^ tok ^ " in expr position")
    end else begin
      expect "(";
      let head = atom () in
      if head = "ret" then begin let v = value () in expect ")"; Ce_ret v end
      else if head = "glob" then begin
        let k = int_of_string (atom ()) in
        if k < 1 then fail (ctx ^ ": (glob N) needs N >= 1 (ident := positive)");
        expect ")"; Ce_glob k
      end
      else if head = "app" then begin
        let a = expr () in let b = expr () in expect ")"; Ce_app (a, b)
      end
      else if head = "tup" then Ce_tup (many expr)
      else if head = "seq" || head = "unify" || head = "choice" then begin
        let a = expr () in let b = expr () in expect ")";
        if head = "seq" then Ce_seq (a, b)
        else if head = "unify" then Ce_unify (a, b)
        else Ce_choice (a, b)
      end
      else if head = "block" then begin
        expect "(";
        let slots = many slot in
        let body = expr () in expect ")"; Ce_block (slots, body)
      end
      else if head = "iter" then begin
        let comb = atom () in ignore (lookup comb_table comb "iter");
        let a = expr () in let b = expr () in expect ")"; Ce_iter (comb, a, b)
      end
      else fail (ctx ^ ": unknown form " ^ head)
    end
  in
  (* the `cands` field: a run of forms, in the order the candidate bag must return *)
  let rec more acc =
    match peek () with
    | None -> List.rev acc
    | Some ")" -> fail (ctx ^ ": unexpected ) in a form list")
    | Some _ -> more (expr () :: acc)
  in
  if multi then
    match more [] with
    | [] -> fail (ctx ^ ": expected at least one form")
    | xs -> xs
  else begin
    let out = expr () in
    if peek () <> None then fail (ctx ^ ": trailing tokens in form");
    [ out ]
  end

(* `expr`, `norm` and any other single-form field go through the same parser. *)
let read_form ctx line =
  match read_forms ctx line with
  | [ e ] -> e
  | _ -> fail (ctx ^ ": expected exactly one form")

(* ---------- corpus file: case blocks with head/expr/norm/cands/cands_why/why/fuel *)

let read_lines path =
  let ic = open_in path in
  let rec go acc =
    match input_line ic with
    | line -> go (line :: acc)
    | exception End_of_file -> close_in ic; List.rev acc
  in
  go []

let strip s =
  let i = ref 0 in
  let n = String.length s in
  while !i < n && (s.[!i] = ' ' || s.[!i] = '\t' || s.[!i] = '\r') do incr i done;
  let j = ref n in
  while !j > !i && (s.[!j - 1] = ' ' || s.[!j - 1] = '\t' || s.[!j - 1] = '\r') do decr j done;
  String.sub s !i (!j - !i)

let quoted ctx rest =
  let n = String.length rest in
  if n < 2 || rest.[0] <> '"' || rest.[n - 1] <> '"' then
    fail (ctx ^ ": why must be a quoted string");
  String.sub rest 1 (n - 2)

(* Case names are also Coq identifier suffixes in the other corner (corpus.py
   emits `c_<name>`), so this reader enforces the same shape: the two readers
   must accept exactly the same file. *)
let valid_name ctx name =
  let alnum c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
              || (c >= '0' && c <= '9') || c = '_' in
  if String.length name = 0 then fail (ctx ^ ": empty case name");
  let first = name.[0] in
  if not ((first >= 'a' && first <= 'z') || (first >= 'A' && first <= 'Z') || first = '_')
  then fail (ctx ^ ": case name " ^ name ^ " must start with a letter");
  if not (String.for_all alnum name) then
    fail (ctx ^ ": case name " ^ name ^ " is not a plain identifier");
  name

let parse_corpus path =
  let cases = ref [] in
  let cur = ref None in
  let fuel_default = ref 24 in
  List.iteri (fun i raw ->
    let line = strip raw in
    if line = "" || line.[0] = '#' then ()
    else begin
      let where = path ^ ":" ^ string_of_int (i + 1) in
      let cut = try Some (String.index line ' ') with Not_found -> None in
      match cut with
      | None -> fail (where ^ ": expected a directive or a case field")
      | Some k ->
        let key = String.sub line 0 k in
        let rest = strip (String.sub line (k + 1) (String.length line - k - 1)) in
        if key = "defaults" then begin
          let parts = String.split_on_char ' ' rest in
          (match parts with
           | [ "fuel"; v ] -> fuel_default := int_of_string v
           | _ -> fail (where ^ ": expected: defaults fuel N"))
        end else if key = "case" then begin
          (match !cur with Some c -> cases := c :: !cases | None -> ());
          let name = valid_name where rest in
          if List.exists (fun c -> c.c_name = name) !cases then
            fail (where ^ ": duplicate case name " ^ name);
          cur := Some { c_name = name; c_fuel = !fuel_default; c_head = H_none;
                        c_expr = Ce_fail; c_norm = Ce_fail; c_why = "";
                        c_cands = None; c_cands_why = "";
                        c_has_head = false; c_has_expr = false; c_has_norm = false }
        end else begin
          match !cur with
          | None -> fail (where ^ ": " ^ key ^ " outside a case block")
          | Some c ->
            let ctx = where ^ " (case " ^ c.c_name ^ " " ^ key ^ ")" in
            if key = "head" then begin
              if rest = "none" then c.c_head <- H_none
              else c.c_head <- H_row (lookup row_table rest "head");
              c.c_has_head <- true
            end else if key = "expr" then begin
              c.c_expr <- read_form (ctx ^ " expr") rest; c.c_has_expr <- true
            end else if key = "norm" then begin
              c.c_norm <- read_form (ctx ^ " norm") rest; c.c_has_norm <- true
            end else if key = "cands" then
              (* Some bag = this case also checks cand_bag on its normal form *)
              c.c_cands <- Some (read_forms ~multi:true (ctx ^ " cands") rest)
            else if key = "cands_why" then c.c_cands_why <- quoted ctx rest
            else if key = "why" then c.c_why <- quoted ctx rest
            else if key = "fuel" then c.c_fuel <- int_of_string rest
            else fail (ctx ^ ": unknown field (head/expr/norm/cands/cands_why/why/fuel)")
        end
    end) (read_lines path);
  (match !cur with Some c -> cases := c :: !cases | None -> ());
  List.iter (fun c ->
    if not c.c_has_head then fail (c.c_name ^ ": no `head` field")
    else if not c.c_has_expr then fail (c.c_name ^ ": no `expr` field")
    else if not c.c_has_norm then fail (c.c_name ^ ": no `norm` field")) !cases;
  List.rev !cases

(* ---------- surface AST -> extracted AST ---------- *)

let rec nat_of k = if k <= 0 then E.O else E.S (nat_of (k - 1))

let rec pos_of k =
  if k = 1 then E.XH
  else if k mod 2 = 0 then E.XO (pos_of (k / 2))
  else E.XI (pos_of (k / 2))

let z_of k = if k = 0 then E.Z0 else if k > 0 then E.Zpos (pos_of k) else E.Zneg (pos_of (-k))

let rec of_list xs = match xs with [] -> E.Nil | x :: r -> E.Cons (x, of_list r)

let rec ty_of = function
  | Cy_unit -> E.TUnit | Cy_bool -> E.TBool | Cy_int -> E.TInt | Cy_any -> E.TAny
  | Cy_arr (a, b) -> E.TArr (ty_of a, ty_of b)

let rec value_of v = match v with
  | Cv_unit -> E.VUnit | Cv_true -> E.VTrue | Cv_false -> E.VFalse
  | Cv_int k -> E.VInt (z_of k)
  | Cv_prim p -> E.VPrim (lookup prim_table p "prim")
  | Cv_tup vs -> E.VTup (of_list (List.map value_of vs))
  | Cv_lam (t, e) -> E.VLam (ty_of t, expr_of e)
  | Cv_delay e -> E.VDelay (expr_of e)
  | Cv_var k -> E.VVar (nat_of k)

and expr_of e = match e with
  | Ce_ret v -> E.Ret (value_of v)
  | Ce_glob k -> E.Glob (pos_of k)
  | Ce_app (a, b) -> E.App (expr_of a, expr_of b)
  | Ce_tup es -> E.TupE (of_list (List.map expr_of es))
  | Ce_seq (a, b) -> E.Seq (expr_of a, expr_of b)
  | Ce_unify (a, b) -> E.Unify (expr_of a, expr_of b)
  | Ce_choice (a, b) -> E.Choice (expr_of a, expr_of b)
  | Ce_fail -> E.Fail
  | Ce_block (slots, body) ->
      E.Block (of_list (List.map (fun (t, ov) ->
        E.Pair (ty_of t, match ov with None -> E.None | Some v -> E.Some (value_of v))) slots),
        expr_of body)
  | Ce_iter (c, a, b) -> E.Iter (lookup comb_table c "iter", expr_of a, expr_of b)

(* ---------- diagnostics: print an extracted term back in the corpus syntax ---------- *)

let rec pos_to_int p = match p with
  | E.XH -> 1
  | E.XO q -> 2 * pos_to_int q
  | E.XI q -> 2 * pos_to_int q + 1

let z_to_int z = match z with
  | E.Z0 -> 0
  | E.Zpos p -> pos_to_int p
  | E.Zneg p -> -(pos_to_int p)

let rec nat_to_int n = match n with E.O -> 0 | E.S k -> 1 + nat_to_int k

let prim_name p =
  match List.filter (fun (_, v) -> v = p) prim_table with
  | (name, _) :: _ -> name
  | [] -> "?"

let comb_name c =
  match List.filter (fun (_, v) -> v = c) comb_table with
  | (name, _) :: _ -> name
  | [] -> "?"

let rec ty_name t = match t with
  | E.TUnit -> "tunit" | E.TBool -> "tbool" | E.TInt -> "tint" | E.TAny -> "tany"
  | E.TArr (a, b) -> "(arr " ^ ty_name a ^ " " ^ ty_name b ^ ")"

let rec to_ocaml_list xs = match xs with E.Nil -> [] | E.Cons (x, r) -> x :: to_ocaml_list r

let rec value_pp v = match v with
  | E.VUnit -> "unit" | E.VTrue -> "true" | E.VFalse -> "false"
  | E.VInt z -> string_of_int (z_to_int z)
  | E.VPrim p -> "(primv " ^ prim_name p ^ ")"
  | E.VTup vs -> "(tupv " ^ String.concat " " (List.map value_pp (to_ocaml_list vs)) ^ ")"
  | E.VLam (t, e) -> "(lam " ^ ty_name t ^ " " ^ expr_pp e ^ ")"
  | E.VDelay e -> "(delay " ^ expr_pp e ^ ")"
  | E.VVar n -> "(var " ^ string_of_int (nat_to_int n) ^ ")"

and slot_pp s = match s with
  | E.Pair (t, E.None) -> "(" ^ ty_name t ^ ")"
  | E.Pair (t, E.Some v) -> "(" ^ ty_name t ^ " " ^ value_pp v ^ ")"

and expr_pp e = match e with
  | E.Ret v -> "(ret " ^ value_pp v ^ ")"
  | E.Glob p -> "(glob " ^ string_of_int (pos_to_int p) ^ ")"
  | E.App (a, b) -> "(app " ^ expr_pp a ^ " " ^ expr_pp b ^ ")"
  | E.TupE es -> "(tup " ^ String.concat " " (List.map expr_pp (to_ocaml_list es)) ^ ")"
  | E.Seq (a, b) -> "(seq " ^ expr_pp a ^ " " ^ expr_pp b ^ ")"
  | E.Unify (a, b) -> "(unify " ^ expr_pp a ^ " " ^ expr_pp b ^ ")"
  | E.Choice (a, b) -> "(choice " ^ expr_pp a ^ " " ^ expr_pp b ^ ")"
  | E.Fail -> "fail"
  | E.Block (slots, body) ->
      "(block (" ^ String.concat " " (List.map slot_pp (to_ocaml_list slots)) ^ ") "
      ^ expr_pp body ^ ")"
  | E.Iter (c, a, b) -> "(iter " ^ comb_name c ^ " " ^ expr_pp a ^ " " ^ expr_pp b ^ ")"

let row_name r =
  match List.filter (fun (_, v) -> v = r) row_table with
  | (name, _) :: _ -> name
  | [] -> "?"

(* ---------- the corner itself ---------- *)

let rows_the_head_table_can_select = to_ocaml_list E.selected_rows

(* A candidate bag printed the way the corpus writes one: alternatives separated by |. *)
let bag_pp es = String.concat " | " (List.map expr_pp (to_ocaml_list es))

let run_case c =
  let e = expr_of c.c_expr in
  let expected = expr_of c.c_norm in
  let fuel = nat_of c.c_fuel in
  let got_row = match E.head_redex e with
    | E.None -> None
    | E.Some (E.Pair (r, _)) -> Some r
  in
  let want_row = match c.c_head with H_none -> None | H_row r -> Some r in
  let row_ok = got_row = want_row in
  let got = E.norm fuel e in
  let norm_ok = got = expected in
  (* `cands` is a claim about cand_bag *on the normal form*, in order: the kernel's
     candidate bag must offer exactly these trees and nothing else. *)
  let cands_want = match c.c_cands with
    | None -> None
    | Some es -> Some (of_list (List.map expr_of es))
  in
  let cands_got = E.cand_bag got in
  let cands_ok = match cands_want with
    | None -> true
    | Some w -> cands_got = w
  in
  let row_in_head_table = match want_row with
    | None -> true
    | Some r -> List.exists (fun x -> x = r) rows_the_head_table_can_select
  in
  if row_ok && norm_ok && cands_ok && row_in_head_table then begin
    Printf.printf "ok    %-38s %s%s\n" c.c_name
      (match want_row with None -> "no row" | Some r -> row_name r)
      (match c.c_cands with
        | None -> ""
        | Some es -> Printf.sprintf "   %d candidate(s)" (List.length es));
    true
  end else begin
    Printf.printf "FAIL  %s  (why: %s)\n" c.c_name c.c_why;
    if not row_ok then begin
      Printf.printf "      head row: expected %s, extracted evaluator selected %s\n"
        (match want_row with None -> "none" | Some r -> row_name r)
        (match got_row with None -> "none" | Some r -> row_name r)
    end;
    if not row_in_head_table then begin
      Printf.printf "      expected row %s is not in the extracted selected_rows list\n"
        (match want_row with Some r -> row_name r | None -> "none")
    end;
    if not norm_ok then begin
      Printf.printf "      norm (fuel %d): got %s\n" c.c_fuel (expr_pp got);
      Printf.printf "                    want %s\n" (expr_pp expected)
    end;
    (match cands_want with
      | None -> ()
      | Some w ->
        if not cands_ok then begin
          Printf.printf "      cand_bag: got  %s\n" (bag_pp cands_got);
          Printf.printf "                want %s\n" (bag_pp w);
          if c.c_cands_why <> "" then
            Printf.printf "                (want this shape because: %s)\n" c.c_cands_why
        end);
    false
  end

let () =
  match List.tl (Array.to_list Sys.argv) with
  | [] | _ :: _ :: _ ->
      prerr_endline "usage: corpus-run CORPUS.texpr"; exit 2
  | path :: _ ->
      let cases = parse_corpus path in
      let n_cands = List.fold_left
        (fun acc c -> match c.c_cands with Some _ -> acc + 1 | None -> acc) 0 cases in
      Printf.printf "timbda corpus corner (extracted evaluator): %s, %d cases\n"
        path (List.length cases);
      let ok = List.fold_left (fun acc c -> if run_case c then acc else false) true cases in
      Printf.printf "cands corner: %d groups, %s\n" n_cands
        (if ok then "all agree with cand_bag" else "see the cand_bag failures above");
      Printf.printf "corpus corner: %d cases, %s\n" (List.length cases)
        (if ok then "all agree with the extracted evaluator" else "MISMATCH");
      if ok then exit 0 else exit 1
