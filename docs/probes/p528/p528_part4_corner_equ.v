(* p7.v - corners via arm-wise unfolding equations + head peels.
   No deep normalization: every denE/denE_tup/apply_c arm is a `reflexivity`-
   level equation rewritten at the head; binds fire via Denotation.bind_sret_l;
   closure uses cbn [] (beta+iota only, empty delta).  (2026-11-26) *)
From Stdlib Require Import ZArith Lia List.
From CTree Require Import CTree Eq.
From CTree.Eq Require Import WBisim.
Import WBisimNotations.
Import EquNotations.
Import CTreeNotations.
Import ListNotations.
Local Open Scope ctree_scope.
Require Import Timbda.Syntax Timbda.Checks Timbda.Semantics Timbda.Eval.
Import Timbda.Denotation.
Local Open Scope Z_scope.

Definition prim_corner (p : Prim) (vs : list Val) : Expr :=
  App (Ret (VPrim p)) (TupE (map Ret vs)).

(* ---------- arm unfoldings (transcribed from Semantics.v, all reflexivity) *)

Lemma denE_App_S (rho : env) (e1 e2 : Expr) (n : nat) :
  denE rho (App e1 e2) (S n)
  = denE rho e1 n >>= fun r1 =>
    match r1 with
    | SOk v1 =>
        match v1 with
        | VTup nil => sret SFail
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
                     | VTup vs => prim_total p vs
                     | v => prim_total p [v]
                     end)).
Proof. reflexivity. Qed.

(* ---------- the corner machine ---------- *)

(* Beta/iota closure with every recursive/fixpoint constant DELTA-BLOCKED:
   unfolding that could re-open the fuel tower is impossible by construction;
   only beta and match-on-constructor reductions can fire.  (cbn [] is a
   syntax error in 9.1; negative delta is the safe spelling.) *)
Ltac beta_iota :=
  cbn -[denE denE_tup apply_c iter_step closeSlots closeV closeE
       prim_total prim_sres unify_top unify_seq sret
       denote prim_corner equ map rev length app
       Z.eqb Z.ltb Z.leb Z.geb orb].

Ltac corner_step :=
  first [ rewrite denE_App_S | rewrite denE_TupE_S
        | rewrite denE_tup_nil_S | rewrite denE_tup_cons_S
        | rewrite denE_ret_S | rewrite apply_c_VPrim_S
        | rewrite bind_sret_l
        | progress (cbn [closeV]) | progress (cbn [prim_total])
        | progress (cbn [prim_sres]) | progress (cbn [rev]) | progress (cbn [app])
        | progress (cbn [map])
        | progress beta_iota ].

Ltac corner_prove :=
  unfold denote, prim_corner; repeat corner_step; reflexivity.

Example c_add :
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

Lemma denote_prim_corner_PGEq : forall x y : Z,
  orb (Z.ltb y x) (Z.eqb x y) = true ->
  denote (prim_corner PGEq [VInt x; VInt y]) 6%nat
  ≅ sret (SOk (VInt x)).
Proof.
  intros x y Hg. unfold denote, prim_corner.
  repeat corner_step. rewrite Hg. beta_iota. reflexivity.
Qed.
