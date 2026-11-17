(* Timbda-0 kernel stub (M-1 skeleton).
   Placeholder for the Gallina canonicalization evaluator (M-2+):
   a tiny locally-Nameless-style term language with one worked reduction. *)

Inductive tm : Type :=
  | tm_var : nat -> tm
  | tm_lam : tm -> tm
  | tm_app : tm -> tm -> tm.

Fixpoint tmempty (t : tm) : tm :=
  match t with
  | tm_var n => tm_var n
  | tm_lam b => tm_lam (tmempty b)
  | tm_app f x => tm_app (tmempty f) (tmempty x)
  end.

Theorem tmempty_id : forall t, tmempty t = t.
Proof.
  induction t; simpl; intros; f_equal; auto.
Qed.

Definition example_redex : tm := tm_app (tm_lam (tm_var 0)) (tm_lam (tm_var 0)).
Example example_normalized : tmempty example_redex = example_redex.
Proof. reflexivity. Qed.
