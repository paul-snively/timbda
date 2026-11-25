(* p524 - T6 increment B: the general induction. Compiles against the
   increment-A store tree (Require Timbda.Realize). This text is what gets
   appended to coq/Realize.v. *)

From Stdlib Require Import ZArith List.
Require Import compcert.lib.Coqlib compcert.lib.Integers compcert.lib.Maps
  compcert.common.Values compcert.common.AST compcert.common.Memory
  compcert.common.Events compcert.common.Globalenvs
  compcert.cfrontend.Ctypes compcert.cfrontend.Cop compcert.cfrontend.Clight
  compcert.cfrontend.ClightBigstep.
Require Import Timbda.Syntax Timbda.Rewriting Timbda.Semantics Timbda.Eval
  Timbda.Checks Timbda.Lower Timbda.Realize.

(* ---------- what the emitted statements write, at the Int64 level ---------- *)

(* z64 is the syntactic mirror of Lower.v's vconst: every Val shape maps to the
   Int64 constant that vconst actually emits (the placeholder arm included). *)
Definition z64 (v : Val) : Int64.int :=
  match v with
  | VInt z => Int64.repr z
  | VTrue  => Int64.repr 1
  | VFalse => Int64.repr 0
  | VUnit  => Int64.repr 0
  | _      => Int64.repr 0
  end.

Definition clight_of_val (v : Val) : val := Vlong (z64 v).

Definition prim_clight (p : Prim) (vs : list Val) : val :=
  match p, vs with
  | PAdd, a :: b :: nil => Vlong (Int64.add (z64 a) (z64 b))
  | PSub, a :: b :: nil => Vlong (Int64.sub (z64 a) (z64 b))
  | PMul, a :: b :: nil => Vlong (Int64.mul (z64 a) (z64 b))
  | PDiv, a :: b :: nil => Vlong (Int64.divs (z64 a) (z64 b))
  | PNeg, a :: nil      => Vlong (Int64.neg (z64 a))
  | PLt,  a :: b :: nil => Val.of_bool (Int64.cmp Clt (z64 a) (z64 b))
  | PGt,  a :: b :: nil => Val.of_bool (Int64.cmp Cgt (z64 a) (z64 b))
  | PLEq, a :: b :: nil => Val.of_bool (Int64.cmp Cle (z64 a) (z64 b))
  | PGEq, a :: b :: nil => Val.of_bool (Int64.cmp Cge (z64 a) (z64 b))
  | PNEq, a :: b :: nil => Val.of_bool (Int64.cmp Cne (z64 a) (z64 b))
  | _, _                 => Vlong (Int64.repr 0)
  end.

Fixpoint last_val (vs : list Val) : option Val :=
  match vs with
  | nil => None
  | v :: nil => Some v
  | _ :: rest => last_val rest
  end.

(* The value the lowered statement leaves in lower_res, computed from the tree:
   a monoid fold over the writes clight_of (lower e) performs, threaded through
   the incoming value o (Seq composes, Block's prelude never names lower_res). *)
Fixpoint lower_final (e : Expr) (o : option val) : option val :=
  match e with
  | Ret v => Some (clight_of_val v)
  | Glob _ => o
  | App f a =>
      match Lower.prim_head f, prim_operand_vals a with
      | Some p, Some vs => Some (prim_clight p vs)
      | _, _ => o
      end
  | TupE es =>
      match rets_of es with
      | Some vs => match last_val vs with
                   | Some v => Some (clight_of_val v)
                   | None => o
                   end
      | None => o
      end
  | Seq e1 e2 => lower_final e2 (lower_final e1 o)
  | Unify _ _ => o
  | Choice _ _ => o
  | Fail => o
  | Iter _ _ _ => o
  | Block _ b => lower_final b o
  end.

(* vconst = Econst_long (z64 v), constructor for constructor. *)
Lemma vconst_z64 : forall v : Val,
  Lower.vconst v = Clight.Econst_long (z64 v) Lower.tint64.
Proof. destruct v; cbn [Lower.vconst z64]; reflexivity. Qed.
