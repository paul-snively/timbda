(* RealizeCorners.v - the exact kernel-side denotation of prim-application
   corners (docs/PLAN.md decision 12; docs/DESIGN-NOTES.md sec. 13.15):
   prim_corner builds `Ret (VPrim p) [TupE (map Ret vs)]`, the fuel of a
   two-operand corner is 6 (`e_fuel`'s TupE arm is S (S (sumE ..))), PNeg's
   corner fuel is 5, and the denotation is pinned at ctrees' structural
   equality `≅`, proved arm-wise: every `denE`/`denE_tup`/`apply_c` arm as a
   `reflexivity`-level unfolding equation rewritten at the head, binds fired
   by Denotation.v's `bind_sret_l` peel, and closure by a BETA_IOTA pass that
   delta-BLOCKS every fixpoint (negative cbn), so nothing can re-open the
   fuel tower.  Kernel side only; the CompCert pairing of these denotations
   lives in RealizeCompose.

   WHY `≅` AND NOT `=` (measured 2026-11-26, docs/probes/p528/README.md):
   `>>=` is ctrees' cofix `subst`; a cofix can only be unstuck under
   `observe`, so no Leibniz equality can express a fired bind chain
   (docs/DESIGN-NOTES.md sec. 4.1 ruling; ctrees Core/CTreeDefinitions.v
   says the same: its monad-law lemmas exist only at `equ`).  The conjuncts
   here are therefore `denote corner fuel ≅ sret (SOk v)`.

   WHY NOT A NORMALIZER (measured 2026-11-26): the previous `denorm` full-cbv
   - and Denotation.v's `kernel_cbn` - explode on CONCRETE fuel: cbv is
   strict and cbn descends every stuck match branch, re-unfolding the fixpoint
   per branch per fuel layer.  Measured ladder on the add corner with
   kernel_cbn: 1 s at fuel 4, 18 s at fuel 5, > 90 s (stall) at fuel 6, and
   the uncapped 61 GiB rocqworker earlyoom shot on 2026-11-26 was this shape.
   Denotation.v survives only because its lemmas carry SYMBOLIC fuel
   (`S (S f)`), which cbn cannot descend past.  Corners are concrete - hence
   the arm-equation route, which touches one arm per rewrite and is linear by
   construction.  Toolchain traps measured in the same probe run: `unfold a b`
   is a syntax error (commas); `cbn [a, b]` is a syntax error (spaces);
   `cbn []` is a syntax error (negative delta `cbn -[...]` is the safe
   all-blocked spelling); cbn with a delta list does NOT unfold `denote` /
   `prim_corner` when they sit in the argument positions of the equ goal -
   enter goals with `unfold`; keep `Z.eqb`/`Z.ltb`/`orb` delta-blocked so the
   guard hypotheses still match their occurrences (same ruling as
   Denotation.v sec. "shared cbn vocabulary"); Stdlib.Bool is NOT imported
   (the `&&&` clash ruling), so PGEq's guard is spelled `orb (..) (..)`.

   BUILD-UNIT POLICY (measured 2026-11-26): the T6 realization side is a
   fan-in - leaves RealizeBridges / RealizeDiv / RealizeCorners compose in
   RealizeCompose, and Realize.v is the CompCert-side hub the leaves read.
   Each increment lands in its own leaf so a single coqc unit never re-checks
   the accumulated history; the gate's Coq lane runs dune with (jobs 1)
   (coq/dune-workspace).  This leaf is kernel-side only (no compcert imports,
   like Denotation.v) and compiles in ~2 s end to end.
   AUDIT.  CompCert-cone-facing: audited by the flake timbda-kernel buildPhase
   cone sweep (rocq check on Timbda.Realize + Timbda.RealizeCompose, which
   transitively cover this file).  No `Print Assumptions` line here -
   forbidden in the whole Realize family: its output would land in build.log
   and break the kernel sweep. *)

From Stdlib Require Import ZArith Lia List.
From CTree Require Import CTree Eq.
From CTree.Eq Require Import WBisim.
Import WBisimNotations.
Import EquNotations.
Import CTreeNotations.
Import ListNotations.
Local Open Scope ctree_scope.
(* Z scope after the Timbda Require block (toolchain ruling, same as the
   pre-split Realize.v). *)
Require Import Timbda.Syntax Timbda.Checks Timbda.Semantics Timbda.Eval.
(* Denotation.v arrives transitively through Timbda.Checks; the Import puts
   its shared vocabulary (`bind_sret_l`) in scope for the peeling loop. *)
Import Timbda.Denotation.
Local Open Scope Z_scope.

(* ---------- the exact kernel-side corner expression ---------- *)

Definition prim_corner (p : Prim) (vs : list Val) : Expr :=
  App (Ret (VPrim p)) (TupE (map Ret vs)).

Lemma rets_of_map_ret : forall (vs : list Val),
  rets_of (map Ret vs) = Some vs.
Proof.
  induction vs as [| v vs IHvs]; cbn [map rets_of];
    [reflexivity | rewrite IHvs; reflexivity].
Qed.

Lemma e_fuel_prim_corner2 : forall (p : Prim) (u v : Val),
  e_fuel (prim_corner p [u; v]) = 6%nat.
Proof.
  intros p u v. unfold prim_corner.
  cbn [e_fuel sumE map].
  (* nat `+` is a Fixpoint not in the delta list (lia also refuses the bare
     numeral equation here - "Cannot find witness"); full cbn reduces it. *)
  cbn. reflexivity.
Qed.

(* ---------- arm unfoldings (transcribed from Semantics.v) ----------
   Each is definitional: the fuel arm fires on `S n`, the Expr/Val arm on the
   constructor, so plain `reflexivity` closes them - no normalization of the
   rest of the term, no delta exposure. *)

Lemma denE_App_S (rho : env) (e1 e2 : Expr) (n : nat) :
  denE rho (App e1 e2) (S n)
  = denE rho e1 n >>= fun r1 =>
    match r1 with
    | SOk v1 =>
        match v1 with
        | VTup nil => sret SFail          (* beta-t0: fail without forcing e *)
        | _ =>
            denE rho e2 n >>= fun r2 =>
            match r2 with
            | SOk v2 => apply_c rho n v1 v2
            | SFail => sret SFail
            | SStuck => sret SStuck
            end
        end
    | SFail => sret SFail
    | SStuck => sret SStuck
    end.
Proof. reflexivity. Qed.

Lemma denE_TupE_S (rho : env) (es : list Expr) (n : nat) :
  denE rho (TupE es) (S n) = denE_tup rho es nil n.
Proof. reflexivity. Qed.

Lemma denE_tup_nil_S (rho : env) (acc : list Val) (n : nat) :
  denE_tup rho nil acc (S n) = sret (SOk (VTup (rev acc))).
Proof. reflexivity. Qed.

Lemma denE_tup_cons_S (rho : env) (e : Expr) (rest : list Expr)
    (acc : list Val) (n : nat) :
  denE_tup rho (e :: rest) acc (S n)
  = denE rho e n >>= fun r =>
    match r with
    | SOk v => denE_tup rho rest (v :: acc) n
    | SFail => sret SFail
    | SStuck => sret SStuck
    end.
Proof. reflexivity. Qed.

Lemma apply_c_VPrim_S (rho : env) (p : Prim) (arg : Val) (n : nat) :
  apply_c rho (S n) (VPrim p) arg
  = sret (prim_sres (match arg with
                     | VTup vs => prim_total p vs   (* decision 5 *)
                     | v => prim_total p [v]
                     end)).
Proof. reflexivity. Qed.

(* ---------- the corner machine ----------
   beta_iota: beta + match-on-constructor closure with EVERY recursive
   constant delta-blocked (negative cbn list).  Unfolding that could re-open
   the fuel tower - the evaluator fixpoints, list fixpoints, and the Z guard
   functions whose hypotheses must stay matchable - is impossible by
   construction. *)

Ltac beta_iota :=
  cbn -[denE denE_tup apply_c iter_step closeSlots closeV closeE
       prim_total prim_sres unify_top unify_seq sret
       denote prim_corner equ map rev length app
       Z.eqb Z.ltb Z.leb Z.geb orb].

Ltac corner_step :=
  first [ rewrite denE_App_S | rewrite denE_TupE_S
        | rewrite denE_tup_nil_S | rewrite denE_tup_cons_S
        | rewrite denE_ret_S            (* Denotation.v's green Ret-arm lemma *)
        | rewrite apply_c_VPrim_S
        | rewrite bind_sret_l           (* Denotation.v's kernel-headed bind law *)
        | progress (cbn [closeV]) | progress (cbn [prim_total])
        | progress (cbn [prim_sres]) | progress (cbn [rev])
        | progress (cbn [app]) | progress (cbn [map])
        | progress beta_iota ].

Ltac corner_prove :=
  unfold denote, prim_corner; repeat corner_step; reflexivity.

(* The guard-success readings that the T6 hypotheses need (used by
   RealizeCompose's det_struct witnesses).  They must be stated as lemmas, not
   normalization: det_struct normalizes the guard occurrence only after
   app_node_ok is DELTA-FOLDED, and cbn refuses (reverts) that fold while the
   guard is symbolic - measured 2026-11-26: `cbn [det_struct ... app_node_ok
   ...]` on the PGt corner returns the goal UNCHANGED.  The `unfold` route is
   safe here (no fuel tower: these are kernel booleans), but an `unfold` of the
   mutual guards (bans_okE/blocks_closed_okE) rewrites them into raw fix terms,
   so the shared prologue folds only the non-mutual constants and cbn finishes
   the mutual ones.  The failed-guard branch is NOT true - `prim_args_ok` is
   the structural-prim arity check, false for PGt/PDiv - so the guard
   hypothesis is genuinely required (probe p20 measured the false branch). *)

Lemma prim_total_res_PGt_true : forall x y : Z,
  Z.ltb y x = true -> prim_total_res PGt [VInt x; VInt y] = true.
Proof.
  intros x y Hg. unfold prim_total_res. cbn [prim_total]. rewrite Hg. reflexivity.
Qed.

Lemma prim_total_res_PDiv_true : forall x y : Z,
  Z.eqb y 0 = false -> prim_total_res PDiv [VInt x; VInt y] = true.
Proof.
  intros x y Hz. unfold prim_total_res. cbn [prim_total]. rewrite Hz. reflexivity.
Qed.

Ltac hds_corner_prologue :=
  unfold prim_corner;
  unfold det_struct, apps_okE, tup_rets_okE, app_node_ok, prim_operand_vals, rets_of, map.

Ltac hds_corner_finish :=
  cbn [bans_okE blocks_closed_okE unify_okE apps_okE tup_rets_okE app_node_ok
       all_int Rewriting.is_int_val prim_total_res prim_total andb forallb];
  reflexivity.

Ltac hds_guarded Hres :=
  cbn [bans_okE blocks_closed_okE unify_okE andb forallb all_int Rewriting.is_int_val];
  rewrite Hres;
  cbn [apps_okE tup_rets_okE app_node_ok prim_total_res prim_total andb forallb];
  reflexivity.

(* machine check (the cbv/cbn beta question, micro27/28 ruling, re-landed at
   ≅): the concrete add corner really denotes VInt 5 at fuel 6.  The pre-split
   spellings (vm_compute / full cbv) on the fuel-6 ctrees were measured
   2026-11-26 to grind > 40 min capped at 8 GiB; uncapped the same shape
   reached 61 GiB before earlyoom shot it (docs/probes/p528/README.md). *)
Example denote_add_corner_2_3 :
  denote (prim_corner PAdd [VInt 2; VInt 3]) 6%nat ≅ sret (SOk (VInt 5)).
Proof. corner_prove. Qed.

Lemma denote_prim_corner_PAdd : forall x y : Z,
  denote (prim_corner PAdd [VInt x; VInt y]) 6%nat
  ≅ sret (SOk (VInt (x + y))).
Proof. intros x y. corner_prove. Qed.

Lemma denote_prim_corner_PSub : forall x y : Z,
  denote (prim_corner PSub [VInt x; VInt y]) 6%nat
  ≅ sret (SOk (VInt (x - y))).
Proof. intros x y. corner_prove. Qed.

Lemma denote_prim_corner_PDiv : forall x y : Z,
  Z.eqb y 0 = false ->
  denote (prim_corner PDiv [VInt x; VInt y]) 6%nat
  ≅ sret (SOk (VInt (Z.div x y))).
Proof.
  intros x y Hz. unfold denote, prim_corner.
  repeat corner_step. rewrite Hz. beta_iota. reflexivity.
Qed.

(* PNeg's corner fuel is e_fuel = S (S (S (S 1))) = 5: the one-element TupE
   consumes two fuel layers (cons arm, then the nil arm one layer down), so
   fuel 3 or 4 lands the element evaluation at the fuel-0 `sret SStuck` arm -
   measured 2026-11-26. *)
Lemma denote_prim_corner_PNeg : forall x : Z,
  denote (prim_corner PNeg [VInt x]) 5%nat
  ≅ sret (SOk (VInt (- x))).
Proof. intros x. corner_prove. Qed.

Lemma denote_prim_corner_PGt : forall x y : Z,
  Z.ltb y x = true ->
  denote (prim_corner PGt [VInt x; VInt y]) 6%nat
  ≅ sret (SOk (VInt x)).
Proof.
  intros x y Hg. unfold denote, prim_corner.
  repeat corner_step. rewrite Hg. beta_iota. reflexivity.
Qed.

(* Stdlib.Bool is deliberately not imported anywhere in the Realize family
   (Denotation.v's `&&&`-clash ruling), so the PGEq guard is spelled `orb`,
   the constant the `||` notation elaborates to in Syntax.v. *)
Lemma denote_prim_corner_PGEq : forall x y : Z,
  orb (Z.ltb y x) (Z.eqb x y) = true ->
  denote (prim_corner PGEq [VInt x; VInt y]) 6%nat
  ≅ sret (SOk (VInt x)).
Proof.
  intros x y Hg. unfold denote, prim_corner.
  repeat corner_step. rewrite Hg. beta_iota. reflexivity.
Qed.
