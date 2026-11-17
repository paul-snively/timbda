(* M0 API probe for the vendored ctrees stack: pure-effect ctree with the
   binary-branch bifunctor B2, and the br2 algebraic laws the kernel's choice
   handling relies on (docs/DESIGN-NOTES.md). *)
From CTree Require Import CTree Eq.
From Stdlib Require Import ZArith List.

Example ex_br2_commut : forall (t u : ctree void1 B2 nat), br2 t u ~ br2 u t.
Proof. intros. apply br2_commut. Qed.

Example ex_br2_assoc : forall (t u v : ctree void1 B2 nat),
    br2 (br2 t u) v ~ br2 t (br2 u v).
Proof. intros. apply br2_assoc. Qed.

Example ex_br2_idem : forall (t : ctree void1 B2 nat), br2 t t ~ t.
Proof. intros. apply br2_idem. Qed.

Example ex_br2_stuck : forall (t : ctree void1 B2 nat), br2 Stuck t ~ t.
Proof. intros. apply br2_stuck_l. Qed.
