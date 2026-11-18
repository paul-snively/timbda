(* Timbda-0 kernel: Core Verse syntax.

   Transcription source: docs/VERSE-RULES.md § 0 (paper Fig. 6, lines 319-357).
   Conventions (recorded in docs/VERSE-RULES.md § 0 / docs/RULES-AUDIT.md):

   - Locals are de Bruijn indices, innermost binder = 0 (Weirich autosubst idiom:
     raw AST + a disciplined lift/shrink, cf. PLAN § 5.2 "well-scoped ASTs").
   - Blocks (`block{∃X{hp}. e}`, Fig. 6 line 334): slot list X written
     outermost-first, so slot i sees the slots listed before it (nearest listed
     = innermost at its position), the body sees all |X| slots (index 0 = last
     listed = innermost). Slots may be declared-but-unvalued (`None`): they are
     the domain of the promote rules (Fig. 8, Tier 2 — semantics via the
     rewriting relation, see Rewriting.v header). Non-recursive slots only
     (recursive heaps = Gc-Rec/Def-Rec Tier-2 rows).
   - Heap entries/values are head-normal forms (line 326): literals, primitive
     heads, tuples, lambdas, delay{e}, bare variables (`v ::= x`). *)

From Stdlib Require Import ZArith Bool List Ascii.
Import ListNotations.

Set Implicit Arguments.

(* Interned identifiers (verse/host globals), PLAN § 5.1. *)
Definition ident := positive.

(* Core Verse type table (PLAN § 4.1). `TAny` is a kernel-side encoding
   placeholder: the paper's block binders `∃x{}` (beta-l, beta-t, for) carry no
   static type at the rewrite-rule site; recorded in docs/RULES-AUDIT.md. *)
Inductive Ty : Type :=
| TUnit : Ty
| TBool : Ty
| TInt  : Ty
| TArr  : Ty -> Ty -> Ty
| TAny  : Ty.

(* Primitive operations. Fig. 10 (lines 452-459) named rules: Add, Gt (gt1/gt2),
   IsInt (isInt1/isInt2), Cons, DotDot. PSub/PMul/PDiv/PNeg/PPls/PLt/PGEq/PLEq/
   PNEq/PIsBool/PIsUnit/PArrLen mirror the pinned verse-semantics `PrimOp` enum
   (Core/Expr.hs); PCons2 is a kernel helper for the Fig. 13 `for` rule
   (`cons2`). The tier of each is recorded in docs/VERSE-RULES.md § 3. *)
Inductive Prim : Type :=
| PAdd | PSub | PMul | PDiv | PNeg | PPls
| PGt | PLt | PGEq | PLEq | PNEq
| PIsInt | PIsBool | PIsUnit
| PCons | PCons2 | PDotDot | PArrLen.

(* iter combinators (Fig. 6 line 342: ic ::= all | if | for). *)
Inductive IterComb : Type := IAll | IIf | IFor.

(* Values: `v ::= x | hnf`, `hnf ::= k | r | ⟨v1..vn⟩ | λx.b | delay{e}`
   (lines 325-326). Skolems `r` and the Essential nodes (`⇝w`, `verify`, `▷`)
   have no kernel constructors (Tier-2 audit rows, docs/VERSE-RULES.md § 0/§ 4). *)
Inductive Val : Type :=
| VUnit  : Val
| VTrue  : Val
| VFalse : Val
| VInt   : Z -> Val
| VPrim  : Prim -> Val
| VTup   : list Val -> Val
| VLam   : Ty -> Expr -> Val
| VDelay : Expr -> Val
| VVar   : nat -> Val

(* Expressions: Fig. 6 lines 327-331, Core-Verse fragment:
     e ::= v | e1 [e2] | e1 ; e2 | e1 = e2 | b1 b2 | fail
         | iter(ic){b}{e} | block{b}
   `block{b}` = Block (b = ∃X{hp}. e); source `def`/`where` desugar into it.
   Host/verse globals enter as `Glob`; host primitives (the targets of the
   canonicalizer `get`/`put` lowerings, PLAN § 4.1, exercised only at M4/T12)
   reach the kernel as applications of Glob heads. *)
with Expr : Type :=
| Ret    : Val -> Expr
| Glob   : ident -> Expr
| App    : Expr -> Expr -> Expr              (* e1 [e2] *)
| TupE   : list Expr -> Expr
           (* expression-level tuple: the canonical core encoding of the paper's
              multi-argument sugar `op[a1, a2]` (line 452, 463) and of the
              Fig. 13 `cons [B [v ], e]` / `cons2 [⟨x , B [v ]⟩, e]` right-hand
              sides, whose arguments are *open expressions* (blocks), not values.
              Documented kernel-side encoding choice in docs/VERSE-RULES.md § 0:
              Fig. 6's `e1 [e2 ]` has a single expression argument. When all
              entries are Ret values, TupE is the value tuple ⟨v1..vn⟩. *)
| Seq    : Expr -> Expr -> Expr              (* e1 ; e2 *)
| Unify  : Expr -> Expr -> Expr              (* e1 = e2 *)
| Choice : Expr -> Expr -> Expr              (* b1 b2 juxtaposition = canonical `or` *)
| Fail   : Expr
| Block  : list (Ty * option Val) -> Expr -> Expr
| Iter   : IterComb -> Expr -> Expr -> Expr  (* iter(ic){b}{e} *)
.

(* ---------- Evaluation contexts C (Fig. 6 line 351) ----------
   C ::= □ | e = C | C = e | e ; C | C ; e | e [C ] | C [e].
   Fig. 7's leftChoiceFree lacks a clause for `C [e]`; the kernel defines it as
   False, a documented kernel-side extension (docs/VERSE-RULES.md § 1). *)
Inductive CtxC : Type :=
| HC_Hole : CtxC
| HC_EqL  : Expr -> CtxC -> CtxC   (* e = C *)
| HC_EqR  : CtxC -> Expr -> CtxC   (* C = e *)
| HC_SeqL : Expr -> CtxC -> CtxC   (* e ; C *)
| HC_SeqR : CtxC -> Expr -> CtxC   (* C ; e *)
| HC_AppL : Expr -> CtxC -> CtxC   (* e [C] *)
| HC_AppR : CtxC -> Expr -> CtxC   (* C [e] *)
.

Fixpoint fillC (k : CtxC) (e : Expr) : Expr :=
  match k with
  | HC_Hole => e
  | HC_EqL e1 k' => Unify e1 (fillC k' e)
  | HC_EqR k' e2 => Unify (fillC k' e) e2
  | HC_SeqL e1 k' => Seq e1 (fillC k' e)
  | HC_SeqR k' e2 => Seq (fillC k' e) e2
  | HC_AppL e1 k' => App e1 (fillC k' e)
  | HC_AppR k' e2 => App (fillC k' e) e2
  end.

(* ---------- Substitution contexts S (Fig. 6 line 352) ----------
   M0 kernel uses the binder-free expression-level fragment
     S ::= □ | e = S | S = e | e ; S | S ; e | e [S ] | S [e].
   The paper's value-context variants (`⟨v1..V..vn⟩`, `λx.B[S ]`, line 355) and
   block variants `B[S ] b`, `b B[S ]` (line 353) are the Subst-Deep / Subst-Var
   / Subst-Block Tier-2 rows deferred to M3. With binder-free S the Fig. 8 side
   condition `x ∉ bvs(S)` is automatic (bvs(S) = ∅): the recorded kernel-side
   restriction. *)
Inductive CtxS : Type :=
| HS_Hole : CtxS
| HS_EqL  : Expr -> CtxS -> CtxS
| HS_EqR  : CtxS -> Expr -> CtxS
| HS_SeqL : Expr -> CtxS -> CtxS
| HS_SeqR : CtxS -> Expr -> CtxS
| HS_AppL : Expr -> CtxS -> CtxS
| HS_AppR : CtxS -> Expr -> CtxS
.

Fixpoint fillS (k : CtxS) (e : Expr) : Expr :=
  match k with
  | HS_Hole => e
  | HS_EqL e1 k' => Unify e1 (fillS k' e)
  | HS_EqR k' e2 => Unify (fillS k' e) e2
  | HS_SeqL e1 k' => Seq e1 (fillS k' e)
  | HS_SeqR k' e2 => Seq (fillS k' e) e2
  | HS_AppL e1 k' => App e1 (fillS k' e)
  | HS_AppR k' e2 => App (fillS k' e) e2
  end.

(* ---------- Lift (Weirich autosubst idiom) ----------
   `liftE k e` shifts the free variables of e up by k, inserting the k binders
   *outside* e. The cutoff d counts binders already crossed; `liftSlotsGo`
   accounts for a block's own prefix slots at each entry position (slot i sees i
   earlier slots).
   Machinery note (Coq 9.1): element<->list mutual `Fixpoint` blocks are rejected
   ("Cannot guess decreasing argument of fix"), so these blocks stay
   element-only and list cases use eta self-calls (`map (liftV k d) vs`); a
   block's per-entry cutoffs go through `walkSlotsV`/`anySlotsV`, total walkers
   parameterised by an opaque callback. See docs/DESIGN-NOTES.md. *)

Fixpoint walkSlotsV (cb : Val -> nat -> Val) (d0 : nat)
  (slots : list (Ty * option Val)) : list (Ty * option Val) :=
  match slots with
  | nil => nil
  | (t, Some v) :: rest => (t, Some (cb v d0)) :: walkSlotsV cb (S d0) rest
  | (t, None) :: rest => (t, None) :: walkSlotsV cb (S d0) rest
  end.

Fixpoint anySlotsV (cb : Val -> nat -> bool) (p0 : nat)
  (slots : list (Ty * option Val)) : bool :=
  match slots with
  | nil => false
  | (_, Some v) :: rest => cb v p0 || anySlotsV cb (S p0) rest
  | (_, None) :: rest => anySlotsV cb (S p0) rest
  end.

Fixpoint liftV (k d : nat) (v : Val) : Val :=
  match v with
  | VVar i => if Nat.ltb i d then VVar i else VVar (i + k)
  | VLam t e => VLam t (liftE k (S d) e)
  | VDelay e => VDelay (liftE k d e)
  | VTup vs => VTup (map (liftV k d) vs)
  | _ => v
  end
with liftE (k d : nat) (e : Expr) : Expr :=
  match e with
  | Ret v => Ret (liftV k d v)
  | Glob g => Glob g
  | App e1 e2 => App (liftE k d e1) (liftE k d e2)
  | TupE es => TupE (map (liftE k d) es)
  | Seq e1 e2 => Seq (liftE k d e1) (liftE k d e2)
  | Unify e1 e2 => Unify (liftE k d e1) (liftE k d e2)
  | Choice e1 e2 => Choice (liftE k d e1) (liftE k d e2)
  | Fail => Fail
  | Iter ic b r => Iter ic (liftE k d b) (liftE k d r)
  | Block slots body =>
      Block (walkSlotsV (fun v i => liftV k (i + d) v) d slots)
            (liftE k (length slots + d) body)
  end.

Definition lift1 (e : Expr) : Expr := liftE 1 0 e.
Definition liftV1 (v : Val) : Val := liftV 1 0 v.

(* ---------- Shrink ----------
   `shrinkE e` removes the innermost binder enclosing e's position (used for GC1:
   the dropped slot of a block, applied to the body which sees it at index 0)
   and reindexes everything above it. Under the GC1 side condition (the dropped
   binder is unused — checked by `occurs` over the whole block, including its
   slots) the `Var d -> Var 0` clause is unreachable junk. *)

Fixpoint shrinkV (d : nat) (v : Val) : Val :=
  match v with
  | VVar i => if Nat.ltb i d then VVar i else if Nat.eqb i d then VVar 0 else VVar (i - 1)
  | VLam t e => VLam t (shrinkE (S d) e)
  | VDelay e => VDelay (shrinkE d e)
  | VTup vs => VTup (map (shrinkV d) vs)
  | _ => v
  end
with shrinkE (d : nat) (e : Expr) : Expr :=
  match e with
  | Ret v => Ret (shrinkV d v)
  | Glob g => Glob g
  | App e1 e2 => App (shrinkE d e1) (shrinkE d e2)
  | TupE es => TupE (map (shrinkE d) es)
  | Seq e1 e2 => Seq (shrinkE d e1) (shrinkE d e2)
  | Unify e1 e2 => Unify (shrinkE d e1) (shrinkE d e2)
  | Choice e1 e2 => Choice (shrinkE d e1) (shrinkE d e2)
  | Fail => Fail
  | Iter ic b r => Iter ic (shrinkE d b) (shrinkE d r)
  | Block slots body =>
      Block (walkSlotsV (fun v i => shrinkV (i + d) v) d slots)
            (shrinkE (length slots + d) body)
  end.

Definition shrink (e : Expr) : Expr := shrinkE 0 e.

(* ---------- occurs: free-variable presence, checked across slots and body ----------
   At a block entry position (slot j listed after j earlier slots), a binder
   external to the block appears at index (target + j); at the body position, at
   index (target + |slots|). These are the two cutoff rules of the conventions in
   the header comment. *)

Fixpoint occursV (i : nat) (v : Val) : bool :=
  match v with
  | VVar j => Nat.eqb i j
  | VLam _ e => occursE (S i) e
  | VDelay e => occursE i e
  | VTup vs => existsb (occursV i) vs
  | _ => false
  end
with occursE (i : nat) (e : Expr) : bool :=
  match e with
  | Ret v => occursV i v
  | Glob _ => false
  | App e1 e2 => occursE i e1 || occursE i e2
  | TupE es => existsb (occursE i) es
  | Seq e1 e2 => occursE i e1 || occursE i e2
  | Unify e1 e2 => occursE i e1 || occursE i e2
  | Choice e1 e2 => occursE i e1 || occursE i e2
  | Fail => false
  | Iter ic b r => occursE i b || occursE i r
  | Block slots body =>
      anySlotsV (fun v j => occursV (i + j) v) 0 slots || occursE (length slots + i) body
  end.

Definition occurs (i : nat) (e : Expr) : bool := occursE i e.

(* ---------- choiceFree / leftChoiceFree (Fig. 7, lines 388-398) ---------- *)
Fixpoint choiceFreeE (e : Expr) : bool :=
  match e with
  | Ret _ => true
  | Glob _ => true
  | App e1 e2 => choiceFreeE e1 && choiceFreeE e2
  | TupE es => forallb choiceFreeE es
  | Seq e1 e2 => choiceFreeE e1 && choiceFreeE e2
  | Unify e1 e2 => choiceFreeE e1 && choiceFreeE e2
  | Choice _ _ => false                      (* choiceFree(b1 b2) = False, line 394 *)
  | Fail => true                             (* line 393 *)
  | Block _ body => choiceFreeE body         (* line 395 *)
  | Iter IAll _ _ => true                    (* line 396 *)
  | Iter IIf _ _ => false                    (* line 397 *)
  | Iter IFor _ base => choiceFreeE base     (* line 398 *)
  end.

Fixpoint leftChoiceFreeC (k : CtxC) : bool :=
  match k with
  | HC_Hole => true                          (* lcf(□) = True, line 381 *)
  | HC_EqR k' _ => leftChoiceFreeC k'        (* lcf(C = e) = lcf(C), line 382 *)
  | HC_SeqR k' _ => leftChoiceFreeC k'       (* lcf(C ; e) = lcf(C), line 383 *)
  | HC_EqL e k' => choiceFreeE e && leftChoiceFreeC k'  (* line 384 *)
  | HC_SeqL e k' => choiceFreeE e && leftChoiceFreeC k' (* line 385 *)
  | HC_AppL _ _ => false                     (* lcf(e [C]) = False, line 386 *)
  | HC_AppR _ _ => false                     (* kernel extension, see CtxC header *)
  end.

(* ---------- Root shapes (Fig. 9 eqfail, line 437; Fig. 9 note lines 441-445;
   Fig. 10 note line 463) ----------
   Two head-normal forms with different roots rewrite to fail (eqfail). Lambda
   equality and variable-variable equality have *no* rule and stay stuck:
   `RLam`/`RootOther` roots admit no Eq constructor in Rewriting.v, and the
   semantics maps them to RStuck. *)
Inductive Root : Type := RInt | RBool | RUnit | RTup | RLam | RDelay | RPrimH | RootOther.

Definition root_of (v : Val) : Root :=
  match v with
  | VInt _ => RInt
  | VTrue | VFalse => RBool
  | VUnit => RUnit
  | VTup _ => RTup
  | VLam _ _ => RLam
  | VDelay _ => RDelay
  | VPrim _ => RPrimH
  | VVar _ => RootOther
  end.

(* ---------- prim_total: kernel reading of Fig. 10 + the pinned verse-semantics
   PrimOp table ----------
   PRes = the rule's value (Fig. 10 left-hand conclusions), PFail = the explicit
   failure rules (gt2, isInt2, …), PStuck = "ill-typed application … is just
   stuck" (line 463). gt keeps the Fig. 10 conclusion shape (`gt[ki1,ki2] → ki1`
   when ki1 > ki2). PDiv on 0 and out-of-shape arguments are PStuck (Div is not
   among Fig. 10's named rules; pinned verse-semantics treats it partial). *)

(* `lo .. hi` in Core Verse is INCLUSIVE on both ends: paper Fig. 10 line 459
   `dotdot[ki1,ki2] -> ki1 (ki1+1) .. ki2` (docs/VERSE-RULES.md sec. 3), the
   pinned oracle `verse-semantics/reduction/Red.hs:1384` (`[IntE i | i <- [l..h]]`,
   Haskell's inclusive `enumFromTo`), and its tests (`tests/tests.versetest`:
   `for(x:=1..3){x}` = `(1,2,3)`, `for(i := 1..4){i+1}` -> 4 elements).  The guard
   is therefore `lo <= hi`: `seq_z lo hi` has exactly `hi - lo + 1` elements for
   `lo <= hi`, which is exactly the fuel `Z.abs (hi - lo) + 1` below, and `nil`
   when `lo > hi` (Haskell's `[l..h] = []` there too).
   Found by the corpus corner: with the previous `Z.ltb` guard `1..3` materialised
   as ⟨1,2⟩.  See docs/DESIGN-NOTES.md sec. 8. *)
Fixpoint seq_z_go (fuel : nat) (lo hi : Z) : list Z :=
  match fuel with
  | 0 => @nil Z
  | S f => if Z.leb lo hi then lo :: seq_z_go f (Z.succ lo) hi else @nil Z
  end.
Definition seq_z (lo hi : Z) : list Z :=
  seq_z_go (Z.to_nat (Z.abs (hi - lo)) + 1) lo hi.

(* Coq 9.1 requires explicit constructor signatures (the old anonymous-parameter
   form `PRes Val` is gone: "Cannot infer the type of Val"). *)
Inductive PrimResult : Type :=
| PRes  : Val -> PrimResult
| PFail : PrimResult
| PStuck : PrimResult.

Definition prim_total (p : Prim) (args : list Val) : PrimResult :=
  match p, args with
  | PAdd, [VInt a; VInt b] => PRes (VInt (a + b))                          (* add, line 452 *)
  | PSub, [VInt a; VInt b] => PRes (VInt (a - b))
  | PMul, [VInt a; VInt b] => PRes (VInt (a * b))
  | PDiv, [VInt a; VInt b] => if Z.eqb b 0 then PStuck else PRes (VInt (a / b))
  | PNeg, [VInt a] => PRes (VInt (- a))
  | PPls, [VInt a] => PRes (VInt a)
  | PPls, [_] => PFail
  | PGt, [VInt a; VInt b] => if Z.ltb b a then PRes (VInt a) else PFail    (* gt1/gt2, 453-454 *)
  | PLt, [VInt a; VInt b] => if Z.ltb a b then PRes (VInt a) else PFail
  | PGEq, [VInt a; VInt b] => if Z.ltb b a || Z.eqb a b then PRes (VInt a) else PFail
  | PLEq, [VInt a; VInt b] => if Z.ltb a b || Z.eqb a b then PRes (VInt a) else PFail
  | PNEq, [VInt a; VInt b] => if Z.eqb a b then PFail else PRes (VInt a)
  | PIsInt, [VInt a] => PRes (VInt a)                                      (* isInt1, line 455 *)
  | PIsInt, [_] => PFail                                                   (* isInt2, line 456 *)
  | PIsBool, [VTrue] => PRes VTrue
  | PIsBool, [VFalse] => PRes VFalse
  | PIsBool, [_] => PFail
  | PIsUnit, [VUnit] => PRes VUnit
  | PIsUnit, [_] => PFail
  | PCons, [v0; VTup vs] => PRes (VTup (v0 :: vs))                        (* cons, line 457 *)
  | PCons, _ => PStuck
  | PCons2, [v1; v2] => PRes (VTup [v1; v2])                              (* Fig. 13 `for` helper *)
  | PDotDot, [VInt a; VInt b] => PRes (VTup (map VInt (seq_z a b)))       (* dotdot, line 459 *)
  | PDotDot, _ => PStuck
  | PArrLen, [VTup vs] => PRes (VInt (Z.of_nat (length vs)))
  | PArrLen, _ => PStuck
  | _, _ => PStuck
  end.
