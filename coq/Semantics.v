(* Timbda-0 kernel: the Core-Verse denotation [[ e ]]  (docs/PLAN.md § 2
   architecture line; docs/VERSE-RULES.md § 6 semantics map; T1/T2 proofs live
   in Denotation.v on top of this file).

   Shape: an ImpBr-style ctrees evaluator (deps/ctrees/examples/ImpBr/ImpBr.v):
   a total Coq Fixpoint producing ctree void1 B2 SResult; Choice maps to br2,
   Fail to ret SFail, stuck roots to ret SStuck.  Pure void1: the Get/Put/Primop
   event signature of PLAN § 2 is the M4 host-verse layer; Core Verse control
   and arithmetic are total and sbisim-provable at the pure level.

   Recorded decisions (mirrored in docs/DESIGN-NOTES.md):

   (1) Env reading per Fig. 5.1 (lines 512-516: E⟦λx.e⟧ ρ = λv. E⟦e⟧ ρ[x := v]):
       semantic function values are kernel lambdas whose enclosing slots were
       substituted (closeV/closeE closure conversion).  Values keep open VVars
       exactly where the kernel does (block-internal slot references, the
       `v ::= x` clause line 325); those resolve when the block evaluates, and
       are stuck_root if scrutinized earlier.

   (2) Fuel: the Fig. 13 iter-choice distribution rebuilds a term as large as
       its input, so it is not structurally recursive.  denoteE carries a
       uniform fuel decremented at every recursive call (uniform-fuel block
       idiom, probes p13c/p14a).  Fuel exhaustion yields SStuck - an artifact
       of the depth budget, not a semantic rule: at every rewrite-rule site the
       corpus evaluation fuel exceeds the boundary, so T1 statements are
       fuel-insensitive where rules fire (the iter rules themselves are the
       admitted Tier-2 corner, Denotation.v).

   (3) Closed-world reading: a block with a declared-unvalued slot (None) is
       SStuck in the denotation.  The declare-then-bind patterns (beta-l's
       `x = e`, promote-l/r, iter-for's `∃x{}`) are Tier-2 rewrite-side
       machinery; the semantics-side counterpart is the M2 state-handler
       (Get/Put events) version.  The corpus and the M1 lowering use direct
       Some-slot blocks, where no divergence arises. *)

From Stdlib Require Import ZArith Bool List.
From CTree Require Import CTree Eq.

Import ListNotations.
Import CTreeNotations.
Local Open Scope ctree_scope.

Require Import Timbda.Syntax Timbda.Rewriting.

(* Pure ctree return under an unqualified name.  ctrees 2.0 exports Ret/Stuck as
   NOTATIONS (Core/CTreeDefinitions.v:102-103, `Ret x := go (RetF x)`), which
   clash with the Expr `Ret` constructor imported from Syntax in this file; the
   disambiguator mis-resolves inside the evaluator, so the evaluator uses sret
   (recorded in docs/DESIGN-NOTES.md).  Patterns stay the Expr constructor. *)
Definition sret {X : Type} (x : X) : ctree void1 B2 X := go (RetF x).

(* Semantic result domain (VERSE-RULES § 6 map):
   SOk = a value candidate (kernel Val, Fig. 6 line 325); SFail = failure,
   i.e. no candidate ("fail as zero", PLAN T2); SStuck = no rule applies
   (Fig. 9 note lines 441-445, Fig. 10 note line 463). *)
Inductive SResult : Type :=
| SOk    : Val -> SResult
| SFail  : SResult
| SStuck : SResult.

(* Frame-stack environment, innermost first: index 0 = innermost binder.
   Invariant: entries are closed values (established by the Ret rule below). *)
Definition env := list Val.

(* ---------- closure conversion (decision 1) ----------
   closeV/closeE substitute rho for the free variables of an open value/expression.
   Cutoff d counts binders crossed that are NOT in rho (own lambda binders, and the
   slot binders of retained blocks); the slot-entry / body-position cutoff rules are
   the ones documented in Syntax.v's header and mirror its liftV/liftE machinery.
   rho lookups that miss (out-of-scope residue) leave the VVar open: stuck_root if
   scrutinized.  Element-only mutual block; list cases via map eta self-calls. *)
Fixpoint closeV (d : nat) (rho : env) (v : Val) : Val :=
  match v with
  | VVar i => if Nat.ltb i d then VVar i
              else match (nth_error rho (i - d)) with
                   | Some v' => v'
                   | None => VVar i
                   end
  | VLam t e => VLam t (closeE (S d) rho e)
  | VDelay e => VDelay (closeE d rho e)
  | VTup vs => VTup (map (closeV d rho) vs)
  | _ => v
  end
with closeE (d : nat) (rho : env) (e : Expr) : Expr :=
  match e with
  | Ret v => Ret (closeV d rho v)
  | Glob g => Glob g
  | App e1 e2 => App (closeE d rho e1) (closeE d rho e2)
  | TupE es => TupE (map (closeE d rho) es)
  | Seq e1 e2 => Seq (closeE d rho e1) (closeE d rho e2)
  | Unify e1 e2 => Unify (closeE d rho e1) (closeE d rho e2)
  | Choice e1 e2 => Choice (closeE d rho e1) (closeE d rho e2)
  | Fail => Fail
  | Iter ic b r => Iter ic (closeE d rho b) (closeE d rho r)
  | Block slots body =>
      Block (walkSlotsV (fun v j => closeV (d + j) rho v) d slots)
            (closeE (d + length slots) rho body)
  end.

(* ---------- unification (Fig. 9, lines 431-445) ----------
   unify_top implements exactly the Fig. 9 rule set on hnf values, reusing the
   root taxonomy of Rewriting.v (root_eqb / no_eq_rule_pair / root_mismatch):
     eqk1    k = k -> k                      (literals, line 432)
     eqk2    k1 = k2 -> fail if k1 <> k2     (line 433)
     eqtup1  equal-length tuples -> componentwise chain, result the left tuple
             (line 435); fold of Rewriting.v's eq_seq
     eqtup2/eqfail  length or root-shape mismatch -> fail (lines 436-437)
     stuck   lambda=lambda, var=var (no_eq_rule_pair), and same-root pairs with
             no rule at all (delay=delay, prim=prim): lines 441-445.
   Seq propagation is folded: a failing component fails the whole chain, a
   stuck component sticks it (a stuck left side of `;` makes no progress).
   Result value of `e1 = e2` is the LEFT side (eqk1 `k = k -> k`,
   eqtup1 `... -> <v1..vn>`), matching the paper's conclusions. *)

Definition lit_eqb (v1 v2 : Val) : bool :=
  match v1, v2 with
  | VUnit, VUnit => true
  | VTrue, VTrue => true
  | VFalse, VFalse => true
  | VInt a, VInt b => Z.eqb a b
  | _, _ => false
  end.

(* Coq 9.1 (DESIGN-NOTES 2): element<->list mutual Fixpoints are rejected outright
   ("principal argument equal to v instead of vs'"), so the unification pair uses
   the validated uniform-fuel block idiom (probe p13c).  Fuel exhaustion yields
   SStuck - a budget artifact, cf. decision 2; each tuple layer consumes exactly
   one fuel unit on both sides of the EqTup1 rule, so T1 statements align. *)
Fixpoint unify_seq (vs : list Val) (ws : list Val) (k : SResult) (f : nat) : SResult :=
  match f with
  | 0 => SStuck
  | S n => match vs, ws with
    | nil, nil => k
    | v :: vs', w :: ws' =>
        match unify_top v w n with
        | SOk _ => unify_seq vs' ws' k n
        | SFail => SFail
        | SStuck => SStuck
        end
    | _, _ => SFail
    end
  end
with unify_top (v1 : Val) (v2 : Val) (f : nat) : SResult :=
  match f with
  | 0 => SStuck
  | S n => match v1, v2 with
    | VTup vs, VTup ws =>
        if Nat.eqb (length vs) (length ws)
        then unify_seq vs ws (SOk (VTup vs)) n
        else SFail
    | _, _ =>
        let r1 := root_of v1 in
        let r2 := root_of v2 in
        if no_eq_rule_pair r1 r2 then SStuck
        else if negb (root_eqb r1 r2) then SFail
        else if is_lit_val v1 && is_lit_val v2
        then if lit_eqb v1 v2 then SOk v1 else SFail
        else SStuck
    end
  end.

(* ---------- block slot pre-pass (Fig. 6 line 334; decision 3) ----------
   closeSlots evaluates the Some-slot hnf values in list order: slot j is closed
   with cutoff 0 under env_j = [w_{j-1}; ... ; w_0] ++ rho (the convention that
   slot j sees its j earlier slots at indices 0..j-1 and the outer env from index
   j on; cf. Syntax.v occurs' entry-position rule).  A None slot (declared but
   unvalued - the domain of promote/beta-l/iter-for's `exists x{}`) yields None:
   its denotation is SStuck; the binding machinery is Tier-2 rewrite-side. *)
Fixpoint closeSlots (env_i : env) (slots : list (Ty * option Val)) : option env :=
  match slots with
  | nil => Some env_i
  | (_, Some v) :: rest => closeSlots (closeV 0 env_i v :: env_i) rest
  | (_, None) :: _ => None
  end.

(* prim_total (Syntax.v, kernel reading of Fig. 10 + the pinned PrimOp table)
   to the semantic result domain (VERSE-RULES § 6 map). *)
Definition prim_sres (r : PrimResult) : SResult :=
  match r with PRes v => SOk v | PFail => SFail | PStuck => SStuck end.

(* ---------- core evaluator (decision 4: engine alignment, pinned Red.hs) ----------
   - iter-if: Red.hs:1647 reduceIter IF blk(Dly e) _ = block{... e}: REPLACEMENT,
     not application; an IIf whose main argument is already a value has no rule
     (Red.hs generic clause: no block redex -> RedNone) and is stuck, agreeing
     with the kernel RewIterIf requiring the delay shape.  Forcing happens ONLY
     through this rule; apply_c never forces a delay.
   - iter-all: Red.hs:1656 cons[B[v], e] (kernel RewIterAll, prim_total PCons).
   - iter-for: the engine rule (Red.hs:1650-1654: declared slot x, cons2 pairing
     over a pair-of-arrays accumulator) is canonicalizer-side (kernel RewIterFor,
     Tier 2).  The denotation takes the documented iterApply path (Core/Expr.hs
     149-154: FOR(v){e0} = x := v[]; ALL{x}): apply the main-argument lambda to
     the empty tuple, then cons.  For well-formed for programs the terminal
     candidate agrees (mfor unpacks the pair accumulator); Tier-2 audit corner
     for the M2 differential harness.
   - application: a lambda binds its (closed) argument value (beta); a primitive
     head goes through prim_total; anything else - literal, tuple, open variable,
     delay - is just stuck (Fig. 10 line 463; no delay-app rule in Red.hs).
     The `v[]` argument is the empty tuple VTup [].
   Fuel (decision 2): every recursive call gets a predecessor, so evaluation is
   total; budget exhaustion yields SStuck.  Choice is br2; stuck/fail propagate
   through sequential positions but survive per-branch inside a choice (a stuck
   branch is an audit leaf while the other branch's candidates live on). *)

Fixpoint denE (rho : env) (e : Expr) (f : nat) : ctree void1 B2 SResult :=
  match f with
  | 0 => sret SStuck
  | S n => match e with
    | Ret v => sret (SOk (closeV 0 rho v))
    | Glob _ => sret SStuck               (* host global: the M4/T12 layer *)
    | Fail => sret SFail
    | Choice e1 e2 => br2 (denE rho e1 n) (denE rho e2 n)
    | Seq e1 e2 =>
        denE rho e1 n >>= fun r1 =>
        match r1 with
        | SOk _ => denE rho e2 n
        | SFail => sret SFail
        | SStuck => sret SStuck
        end
    | Unify e1 e2 =>
        denE rho e1 n >>= fun r1 =>
        match r1 with
        | SOk v1 =>
            denE rho e2 n >>= fun r2 =>
            match r2 with
            | SOk v2 => sret (unify_top v1 v2 n)
            | SFail => sret SFail
            | SStuck => sret SStuck
            end
        | SFail => sret SFail
        | SStuck => sret SStuck
        end
    | App e1 e2 =>
        denE rho e1 n >>= fun r1 =>
        match r1 with
        | SOk v1 =>
            denE rho e2 n >>= fun r2 =>
            match r2 with
            | SOk v2 => apply_c rho n v1 v2
            | SFail => sret SFail
            | SStuck => sret SStuck
            end
        | SFail => sret SFail
        | SStuck => sret SStuck
        end
    | TupE es => denE_tup rho es nil n
    | Block slots body =>
        match (closeSlots rho slots) with
        | Some rho' => denE rho' body n
        | None => sret SStuck             (* decision 3: unvalued slot *)
        end
    | Iter ic b r0 =>
        denE rho b n >>= fun rb =>
        match rb with
        | SOk v => iter_step rho n ic v r0
        | SFail => denE rho r0 n               (* ITER-FAIL: -> the continuation *)
        | SStuck => sret SStuck
        end
    end
  end

with apply_c (rho : env) (f : nat) (fn arg : Val) : ctree void1 B2 SResult :=
  match f with
  | 0 => sret SStuck
  | S n => match fn with
    | VLam _ body => denE (arg :: rho) body n
    | VPrim p => sret (prim_sres (prim_total p [arg]))
    | VDelay _ => sret SStuck             (* forcing only via iter-if *)
    | _ => sret SStuck                    (* ill-typed application, line 463 *)
    end
  end

with iter_step (rho : env) (f : nat) (ic : IterComb) (v : Val) (r : Expr) : ctree void1 B2 SResult :=
  match f with
  | 0 => sret SStuck
  | S n => match ic with
    | IIf =>
        match v with
        | VDelay e1 => denE rho e1 n           (* replacement reading *)
        | _ => sret SStuck
        end
    | IAll =>
        denE rho r n >>= fun rr =>
        match rr with
        | SOk rv => sret (prim_sres (prim_total PCons [v; rv]))
        | SFail => sret SFail
        | SStuck => sret SStuck
        end
    | IFor =>
        apply_c rho n v (VTup (@nil Val)) >>= fun rw =>
        match rw with
        | SOk w =>
            denE rho r n >>= fun rr =>
            match rr with
            | SOk rv => sret (prim_sres (prim_total PCons [w; rv]))
            | SFail => sret SFail
            | SStuck => sret SStuck
            end
        | SFail => sret SFail
        | SStuck => sret SStuck
        end
    end
  end

with denE_tup (rho : env) (es : list Expr) (acc : list Val) (f : nat) : ctree void1 B2 SResult :=
  match f with
  | 0 => sret SStuck
  | S n => match es with
    | nil => sret (SOk (VTup (rev acc)))
    | e :: rest =>
        denE rho e n >>= fun r =>
        match r with
        | SOk v => denE_tup rho rest (v :: acc) n
        | SFail => sret SFail
        | SStuck => sret SStuck
        end
    end
  end.

(* The closed-world top-level denotation [[ e ]].  Fuel is explicit (decision 2):
   tests and the corpus pick a fuel above every rewrite-rule boundary. *)
Definition denote (e : Expr) (fuel : nat) : ctree void1 B2 SResult := denE nil e fuel.
