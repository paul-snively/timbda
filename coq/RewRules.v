(* =====================================================================
    `Rew lhs rhs` : a Core-Verse one-step rewrite at the root of a term.
    It is a *data* type (not a Prop) so that a rule value carries the rule
    identity into the audit tables and into the soundness lemmas
    (`RewSound_<Rule>` in Denotation.v).  Context closure lives in `rw_step` /
    `rewrites` at the end of this file.

    Tier labels follow docs/VERSE-RULES.md and classify the *statement*: Tier 2 =
    the constructor's own statement needs the evolving-heap machinery the M0
    statements omit (promote-l/r's `hp[v/x]` sub-step, float's C-general form);
    Tier 1 = everything else.  Per-ctor proof status (discharged at M0 / deferred,
    with reason class) is the table in docs/RULES-AUDIT.md section 1: tier is not
    status, and a deferred row carries no statement rather than an admitted one.

    GENERATED FILE (M1 item 1, docs/PLAN.md sec. 5.0): every constructor below is
    emitted by dialect/tblgen-rocq -gen-rocq-rules from the TimbdaRuleRecord
    coq* fields of dialect/TimbdaRules.td (records + emission groups maintained
    by tools/rules-coqctor.py).  Regenerate with:
        nix build .#timbda-tblgen-rocq
        tblgen-rocq -gen-rocq-rules dialect/Timbda.td -o coq/RewRules.v
    checks.tblgen-rocq-golden byte-diffs this file against regeneration, and
    tools/rules-audit.py asserts every constructor equals its record fields;
    hand edits here are a gate failure, not a contribution.
    ===================================================================== *)

From Stdlib Require Import ZArith Bool List.
From Timbda Require Import Syntax Rewriting.
Import ListNotations.

Inductive Rew : Expr -> Expr -> Type :=

(* ---------- Fig. 9 (lines 432-437): unification ---------- *)
| RewEqK1 : forall v : Val,
    is_lit_val v = true ->
    Rew (Unify (Ret v) (Ret v)) (Ret v)
    (* audit: EqK1 | fig:9 | tier:1 | k = k -> k (line 432; k ranges over the
        literals unit/true/false/int — the kernel states the literal-general
        form, recorded in docs/RULES-AUDIT.md; eqtup1 handles tuples, eqfail
        the rest) *)
| RewEqK2 : forall v1 v2 : Val,
    is_lit_val v1 = true ->
    is_lit_val v2 = true ->
    v1 <> v2 ->
    Rew (Unify (Ret v1) (Ret v2)) Fail
    (* audit: EqK2 | fig:9 | tier:1 | k1 = k2 -> fail if k1 <> k2 (line 433)
        *)
| RewEqTup1 : forall vs ws : list Val,
    length vs = length ws ->
    Rew (Unify (Ret (VTup vs)) (Ret (VTup ws))) (eq_seq vs ws (Ret (VTup vs)))
    (* audit: EqTup1 | fig:9 | tier:1 | ⟨v1..vn⟩ = ⟨w1..wn⟩ -> v1=w1;
        .. ; vn=wn; ⟨v1..vn⟩ *)
| RewEqTup2 : forall vs ws : list Val,
    length vs <> length ws ->
    Rew (Unify (Ret (VTup vs)) (Ret (VTup ws))) Fail
    (* audit: EqTup2 | fig:9 | tier:1 | ⟨v1..vn⟩ = ⟨w1..wm⟩ -> fail if
        n <> m *)
| RewEqFail : forall v1 v2 : Val,
    root_mismatch v1 v2 = true ->
    Rew (Unify (Ret v1) (Ret v2)) Fail
    (* audit: EqFail | fig:9 | tier:1 | hnf1 = hnf2 -> fail if different root
        shapes; NO rule when either side is a bare variable or both are
        lambdas (no_eq_rule_pair, lines 441-445): those stay stuck *)

(* ---------- Fig. 10 (lines 452-459): primitive operations ----------
   Canonical primop application: `op[a1, a2]` = App (Ret (VPrim op)) (TupE
   [...]). `prim_total` (Syntax.v) is the kernel reading of Fig. 10 plus the
   pinned verse-semantics PrimOp table; `PStuck` means *no rule applies* (line
   463). *)
| RewAdd : forall a b : Z,
    Rew (prim_app PAdd [Ret (VInt a); Ret (VInt b)]) (Ret (VInt (a + b)))
    (* audit: Add | fig:10 | tier:1 | add[ki1, ki2] -> ki1 + ki2 *)
| RewGt1 : forall a b : Z,
    Z.ltb b a = true ->
    Rew (prim_app PGt [Ret (VInt a); Ret (VInt b)]) (Ret (VInt a))
    (* audit: Gt1 | fig:10 | tier:1 | gt[ki1, ki2] -> ki1 if ki1 > ki2 *)
| RewGt2 : forall a b : Z,
    Z.ltb b a = false ->
    Rew (prim_app PGt [Ret (VInt a); Ret (VInt b)]) Fail
    (* audit: Gt2 | fig:10 | tier:1 | gt[ki1, ki2] -> fail if ki1 <= ki2 *)
| RewIsInt1 : forall a : Z,
    Rew (prim_app PIsInt [Ret (VInt a)]) (Ret (VInt a))
    (* audit: IsInt1 | fig:10 | tier:1 | isInt[ki] -> ki *)
| RewIsInt2 : forall v : Val,
    is_int_val v = false ->
    Rew (prim_app PIsInt [Ret v]) Fail
    (* audit: IsInt2 | fig:10 | tier:1 | isInt[v] -> fail if v not an integer
        *)
| RewCons : forall (v0 : Val) (vs : list Val),
    Rew (prim_app PCons [Ret v0; Ret (VTup vs)]) (Ret (VTup (v0 :: vs)))
    (* audit: Cons | fig:10 | tier:1 | cons[v0, ⟨v1..vn⟩] -> ⟨v0, v1,
        .., vn⟩ *)
| RewDotDot : forall a b : Z,
    Rew (prim_app PDotDot [Ret (VInt a); Ret (VInt b)]) (Ret (VTup (map VInt
        (seq_z a b))))
    (* audit: DotDot | fig:10 | tier:1 | dotdot[ki1, ki2] -> ki1 (ki1+1) ..
        ki2; kernel form: the range literal is materialised as a tuple of ints
        *)
| RewPrim : forall (p : Prim) (vs : list Val) (v : Val),
    prim_total p vs = PRes v ->
    Rew (prim_app p (map Ret vs)) (Ret v)
    (* audit: PrimSchema | fig:10 | tier:1 | op[gv ..] -> result of the total
        primop table; SCHEMA record, not one of the 33 named rule rows
        (VERSE-RULES § 3) *)
| RewPrimFail : forall (p : Prim) (vs : list Val),
    prim_total p vs = PFail ->
    Rew (prim_app p (map Ret vs)) Fail
    (* audit: PrimSchemaFail | fig:10 | tier:1 | explicit-failure branch of
        the same schema (gt2/isInt2 are the named instances); SCHEMA record *)

(* ---------- Fig. 11 (lines 468-469): beta reduction ---------- beta-l: the
   paper's side condition `x ∉ fvs(e)` (line 468) is discharged by the
   representation: `e` is lifted past the new slot, and `b` keeps its indices
   because the block's slot 0 replaces the lambda's binder at the same index.
   The kernel's slot is *declared* (`None`) and the binding is written
   literally as the unification `x = e` in the body, exactly as the paper has
   it; `subst`/promote turn it into a heap value binding later (VERSE-RULES §
   3.1). *)
| RewBetaL : forall (t : Ty) (b e : Expr),
    Rew (App (Ret (VLam t b)) e) (Block [(t, @None Val)] (Seq (Unify (Ret
        (VVar 0)) (liftE 1 0 e)) b))
    (* audit: BetaL | fig:11 | tier:1 | (λx.b)[e] -> block{∃x{}. x = e;
        block{b}} *)
| RewBetaT : forall (vs : list Val) (e : Expr),
    vs <> nil ->
    Rew (App (Ret (VTup vs)) e) (Block [(@TAny, @None Val)] (Seq (Unify (Ret
        (VVar 0)) (liftE 1 0 e)) (choice_list (beta_t_cands 0 vs))))
    (* audit: BetaT | fig:11 | tier:1 | ⟨v0,..,vn⟩[e] -> block{∃x{}. x =
        e; ((∃{}. x = 0; v0) .. (∃{}. x = n; vn))}; narrowing; the paper's
        `∃{}` is an empty slot list, hence index-neutral *)
| RewBetaT0 : forall (e : Expr),
    Rew (App (Ret (VTup (@nil Val))) e) Fail
    (* audit: BetaT0 | fig:11 | tier:1 | base case of beta-t: ⟨⟩[e] ->
        fail (line 475); KERNEL-SIDE named rule extracted from that note *)

(* ---------- Fig. 12 (lines 479-491): structural and normalisation ----------
   *)
| RewSeq : forall (v : Val) (e : Expr),
    Rew (Seq (Ret v) e) e
    (* audit: Seq | fig:12 | tier:1 | v ; e -> e *)
| RewNorm1 : forall (v : Val) (e1 e2 : Expr),
    Rew (Unify (Ret v) (Seq e1 e2)) (Seq e1 (Unify (Ret v) e2))
    (* audit: Norm1 | fig:12 | tier:1 | v = (e1 ; e2) -> e1 ; v = e2 *)
| RewNorm2 : forall (v : Val) (e1 e2 : Expr),
    Rew (Unify (Ret v) (Unify e1 e2)) (Seq (Unify (Ret v) e1) (Unify (Ret v)
        e2))
    (* audit: Norm2 | fig:12 | tier:1 | v = (e1 = e2) -> v = e1 ; v = e2 *)
| RewNorm3 : forall (e1 e2 e3 : Expr),
    Rew (Unify (Seq e1 e2) e3) (Seq e1 (Unify e2 e3))
    (* audit: Norm3 | fig:12 | tier:1 | (e1 ; e2) = e3 -> e1 ; e2 = e3 *)
| RewNorm4 : forall (v : Val) (e1 e2 : Expr),
    Rew (Unify (Unify (Ret v) e1) e2) (Seq (Unify (Ret v) e1) (Unify (Ret v)
        e2))
    (* audit: Norm4 | fig:12 | tier:1 | (v = e1) = e2 -> v = e1 ; v = e2
        (progress note, lines 502-503: unifying x with 5 may unlock p) *)
| RewNorm5 : forall (e1 e2 e3 : Expr),
    Rew (Seq (Seq e1 e2) e3) (Seq e1 (Seq e2 e3))
    (* audit: Norm5 | fig:12 | tier:1 | (e1 ; e2) ; e3 -> e1 ; (e2 ; e3)
        (de-clutter, line 504) *)
| RewHpAlpha : forall (slots : list (Ty * option Val)) (body : Expr),
    Rew (Block slots body) (Block slots body)
    (* audit: HpAlpha | fig:12 | tier:1 | ∃X,x{hp}. e <-> ∃X,y{hp[y/x]}.
        e[y/x] if y ∉ fvs(hp,e); representationally trivial under de Bruijn
        (renaming = identity), so this constructor is audit-only and Eval.v's
        strategy table never selects it. The named-syntax rename lives in the
        dialect (M1). *)
| RewLamAlpha : forall (t : Ty) (e : Expr),
    Rew (Ret (VLam t e)) (Ret (VLam t e))
    (* audit: LamAlpha | fig:12 | tier:1 | λx.e <-> λy.e[x/y]; same
        treatment as HpAlpha *)
| RewFloat : forall (sx sy : list (Ty * option Val)) (body : Expr),
    Rew (Block sx (Block sy body)) (Block (sx ++ sy) body)
    (* audit: Float | fig:12 | tier:2 | ∃X{hx}. C[block{∃Y{hy}. e}] ->
        ∃X,Y{hx,hy}. C[e] if X # Y, Y ∉ fvs(C), fvsol(rng(hy)) # X. Two
        kernel-side restrictions, both recorded: (i) the constructor states C
        = □ (the C-general form needs the flatten-substitution lemma,
        M3/T1); (ii) under the outermost-first slot convention the merge is
        *free* — `sx ++ sy` lists the outer slots first, so every slot value
        and the body keep their indices and the paper's freshness side
        conditions hold by construction. *)

(* ---------- Fig. 8 (lines 412-417): substitution and promotion ----------
   `subst`: x = the body-position index of a *valued* slot; S = the
   binder-free CtxS fragment (Syntax.v header: with bvs(S) = empty the paper
   side condition x not in bvs(S) is automatic). The heap entry v lives at the
   slot's own entry position, the occurrence S[x] at the body position:
   `slotValueFromBody` is the reindexing between the two, and the block
   wrapper is common to both sides. *)
| RewSubst : forall slots (p : nat) (v : Val) (k : CtxS),
    slot_value_at slots p = Some v ->
    Rew (Block slots (fillS k (Ret (VVar (slot_body_idx (length slots) p)))))
        (Block slots (fillS k (Ret (slotValueFromBody (length slots) p v))))
    (* audit: Subst | fig:8 | tier:1 | existsX{hp, x v}. S[x] -> existsX{hp, x
        v}. S[v] if x not in bvs(S); binder-free-S kernel restriction + CtxS
        closure recorded *)
| RewGc1 : forall slots (p : nat) (body : Expr),
    slot_value_at slots p <> @None Val ->
    slot_unused (length slots) p slots body = true ->
    Rew (Block slots body) (Block (dropSlot (length slots) p slots) (shrinkE
        (slot_body_idx (length slots) p) body))
    (* audit: Gc1 | fig:8 | tier:1 | existsX,Y{hp}. e -> existsX{hp_Y}. e for
        Y a single unused value binding; the paper's SCC form (recursive
        heaps) is the admitted Tier-2 row `Gc-Rec` (VERSE-RULES 3.2), and the
        non-recursive M0 restriction is recorded there too *)
| RewPromoteL : forall slots (p : nat) (k : CtxC) (v : Val),
    slot_value_at slots p = @None Val ->
    promote_ok (length slots) v = true ->
    promote_hp_ok slots p = true ->
    Rew (Block slots (fillC k (Unify (Ret (VVar (slot_body_idx (length slots)
        p))) (Ret v)))) (Block (fillSlot p (bodyToSlotV (length slots) p v)
        slots) (fillC k (Ret v)))
    (* audit: PromoteL | fig:8 | tier:2 | existsX,x{hp}. C[x = v] ->
        existsX,x{hp[v/x], x v}. C[v]; Tier 2: the constructor carries the
        successful promotion (fill slot + discharge unification to `Ret v`,
        matching eqk1's "unification returns its value"), while `hp[v/x]` is
        restricted to the identity by `promote_hp_ok` — the general
        evolving-heap form is admitted until M3/T1 *)
| RewPromoteR : forall slots (p : nat) (k : CtxC) (v : Val),
    slot_value_at slots p = @None Val ->
    promote_ok (length slots) v = true ->
    promote_hp_ok slots p = true ->
    Rew (Block slots (fillC k (Unify (Ret v) (Ret (VVar (slot_body_idx (length
        slots) p)))))) (Block (fillSlot p (bodyToSlotV (length slots) p v)
        slots) (fillC k (Ret v)))
    (* audit: PromoteR | fig:8 | tier:2 | existsX,x{hp}. C[v = x] -> ... just
        like promote-l (line 417); kept as its own constructor because the
        paper rules out a swap rule (lines 425-428: x = y could loop) *)

(* ---------- Fig. 13 (lines 515-523): iteration and choice ---------- `B[ ]`
   = block contexts `existsX{hp}. hole` (VERSE-RULES 3.4): the kernel states
   each rule as ONE block layer quantified over its slot list, with the plug
   written at the block's body position — exactly where the paper's hole is,
   so no lift is needed for B, and `C[ ]` is the binder-free CtxC fragment
   (leftChoiceFreeC per 1). `iter(all){B[v]}{e}` etc. match only when the hole
   is *directly* filled (with a value / fail / delay / choice), which is the
   paper's intended reading: the iter rule fires once the candidate body has
   reduced to that shape. *)
| RewIterFail : forall (ic : IterComb) (slots : list (Ty * option Val)) (k :
    CtxC) (e : Expr),
    Rew (Iter ic (Block slots (fillC k Fail)) e) e
    (* audit: IterFail | fig:13 | tier:1 | iter(ic){B[C[fail]]}{e} -> e *)
| RewIterChoice : forall (ic : IterComb) (slots : list (Ty * option Val)) (k :
    CtxC) (e1 e2 e : Expr),
    leftChoiceFreeC k = true ->
    Rew (Iter ic (Block slots (fillC k (Choice e1 e2))) e) (Iter ic (Block
        slots (fillC k (Block nil e1))) (Iter ic (Block slots (fillC k (Block
        nil e2))) e))
    (* audit: IterChoice | fig:13 | tier:1 | iter(ic){B[C[b1 b2]]}{e} ->
        iter(ic){B[C[block{b1}]]}{iter(ic){B[C[block{b2}]]}{e}} if
        leftChoiceFree(C); the figure prints the inner continuation as `e3`
        (line 517-518) — read as the shared continuation `e`, as transcribed
        in VERSE-RULES 3.4; kernel Choice = select, `block{b}` = Block nil;
        the ctrees-side soundness of this rule IS the bind/br2 interchange
        (Denotation.v) *)
| RewIterIf : forall (slots : list (Ty * option Val)) (e1 e2 : Expr),
    Rew (Iter IIf (Block slots (Ret (VDelay e1))) e2) (Block nil (Block slots
        e1))
    (* audit: IterIf | fig:13 | tier:1 | iter(if){B[delay{e1}]}{e2} ->
        block{B[e1]} *)
| RewIterAll : forall (slots : list (Ty * option Val)) (v : Val) (e : Expr),
    Rew (Iter IAll (Block slots (Ret v)) e) (prim_app PCons [Block slots (Ret
        v); e])
    (* audit: IterAll | fig:13 | tier:1 | iter(all){B[v]}{e} -> cons[B[v], e];
        `cons[...]` takes open expressions, hence prim_app over TupE *)
| RewIterFor : forall (slots : list (Ty * option Val)) (v : Val) (e : Expr),
    Rew (Iter IFor (Block slots (Ret v)) e) (Block [(@TAny, @None Val)]
        (prim_app PCons2 [TupE [Ret (VVar 0); liftE 1 0 (Block slots (Ret
        v))]; liftE 1 0 e]))
    (* audit: IterFor | fig:13 | tier:1 | iter(for){B[v]}{e} -> block{exists
        x{}. cons2[<x, B[v]>, e]}; the new slot x is declared-unvalued
        (`exists x{}`), and B[v] and e move *inside* it, hence the explicit
        lift-1 (docs/DESIGN-NOTES.md 1); x = body index 0. *)
.

(* ---------- Context closure (the paper's C[ ] / block nesting) ----------
   A rewrite fires at any position reached through evaluation contexts C (Fig. 6
   line 351) or through block bodies.  Rules whose statement already embeds the
   context (subst's S, iter's B/C, promote's C) quantify it directly; the closure
   below supplies the remaining positions.  Rewriting *slot values* in place
   (the paper's `B[S ] b` / `lambda x.B[S ]` contexts, line 353-355) is the
   Subst-Deep Tier-2 row - deferred to M3, recorded in docs/RULES-AUDIT.md. *)
Inductive rw_step : Expr -> Expr -> Prop :=
| rw_here : forall lhs rhs, Rew lhs rhs -> rw_step lhs rhs
| rw_ctx  : forall k lhs rhs, rw_step lhs rhs -> rw_step (fillC k lhs) (fillC k rhs)
| rw_blk  : forall slots lhs rhs, rw_step lhs rhs -> rw_step (Block slots lhs) (Block slots rhs).

Definition rewrites (lhs rhs : Expr) : Prop := rw_step lhs rhs.
