(* Compile.v - docs/PLAN.md M2's CertiRocq->C wiring (decision 9's order: after T6),
   increment D1, per docs/COMPILE-STRATEGY.md sec. 3 and its sec. 8 landing sequence:
   "smallest corner first (Ret/Fail/Seq - already proven as b_ret/b_fail/b_seq)".
   Shape ruled by decision 14 (a fold-specialized hylomorphism; probe docs/probes/p529/),
   carrier ruled by decision 15 (scoped commutativity; materialized choice nodes).

   WHAT THIS FILE IS.  `compile` is ctrees' `fold` (CTree/Interp/Fold.v:28-45)
   specialized to a Clight accumulator the target supplies: the coalgebra is the
   kernel's own `observe` on `denE` output (ctrees exposes exactly one `ctreeF`
   constructor per step); the algebra is `cstate`'s fragment list over the landed
   `Lower.v` spelling (`lower_res`, `vconst`); the hylo is the one `fold`.  The
   compiler never builds the carrier - it consumes the kernel's cofixes one
   observation at a time.  What the fold PRODUCES is concrete finite data at
   Leibniz `=` (every specimen here is `reflexivity`); what it CONSUMES is
   denotation, and no goal in this file rewrites the source side at all - the
   regime split of decision 12f/15 is enforced by there being nothing to split
   (strategy sec. 2, "the regime split, now law").

   THE OBSERVATION FACT D1 MEASURES (what the algebra can see).  `void1` has no
   constructors, so on `ctree void1 B2 SResult` the observable heads are `RetF`
   and `BrF` only: a determinate straight-line program's whole `denE` spine is a
   chain of `sret`/bind layers, and a bind on a `RetF` head IS an iota step
   inside `observe` (p529 law 4) - the spine collapses to its final `RetF`, one
   observation.  The emitted Clight is therefore value-faithful straight-line
   code: the terminal write is pinned through the landed `Lower.v` machinery,
   never re-derived.  `BrF` is the `br2` candidate decision (p529 law 3); the
   scheduler that may answer it - the candidate-existence certificate of
   decision 15 - lands with the choice corner (D4), so in D1 the algebra's `g`
   is the documented TRAP: a choice the determinacy analysis has not yet earned
   has no defined emitted C at all, which is the `FoldCTree.v` CounterExample
   horn (p529 law 3) stated instead of smuggled.

   TWO STUCKS, permanently distinct (p529 law 2; decision 12f).  A kernel fuel
   exhaustion is a RESULT: `denE rho e 0 = sret SStuck` propagates through the
   bind spine and the compile carries it as a `CDone` value (specimen
   `c_kernel_fuel_nest` - no `CLoop`, nothing loop-shaped).  A compile fuel
   exhaustion is a VERDICT: the target's fuel-decreasing `iter` cannot ask for
   the next observation, and `compile` stops at `CLoop` (`c_compile_fuel`).  The
   strategy makes the loop node's absence the claim: the resumption boundary is
   the `CLoop` verdict itself, a claim about the verdict, not an invented
   instruction.

   BUILD-UNIT POLICY (decision 12e, strategy sec. 5): `Compile.v` is a LEAF -
   the hub `Realize.v` is untouched - and it joins the fan-in family that reads
   the hub (RealizeBridges/RealizeDiv/RealizeCorners/RealizeCompose).  Budget:
   every unit under 1 GiB; D1's peak is the CTree+Clight import (~454 MiB
   measured at p529), not the proofs.

   AUDIT.  CompCert-cone-facing: audited by the flake timbda-kernel buildPhase
   cone sweep, which gains `Timbda.Compile` as a third root; the 13-axiom
   context (decision 10a) must print UNCHANGED - the fold path adds no axioms
   (p529: four `Closed under the global context` outputs on the fold's central
   goals), and this file's Clight side is the already-pinned Realize cone.  No
   `Print Assumptions` line here - forbidden in the whole cone family: its
   output would land in build.log and break the kernel sweep. *)

(* Import order follows the RealizeCompose ruling (toolchain, DESIGN-NOTES sec.
   13.15): compcert block first, then the ctrees/ExtLib/ITree classes, then the
   Timbda tree; Z scope and list notations open only after those windows.  The
   p529 trap list is respected throughout: patterns on the parameterized
   `CRes`/`ctreeF` carry `@`; class-supplied binders are parenthesized;
   `MonadIter`'s field order is {R I}; morphisms are spelled with named
   binders; `ctree_scope` stays CLOSED so `~>` is unambiguous. *)
From Stdlib Require Import ZArith List.
Require Import compcert.lib.Coqlib compcert.lib.Integers compcert.lib.Maps
  compcert.common.Values compcert.common.AST compcert.common.Memory
  compcert.common.Events compcert.common.Globalenvs
  compcert.cfrontend.Ctypes compcert.cfrontend.Cop compcert.cfrontend.Clight
  compcert.cfrontend.ClightBigstep.
From CTree Require Import CTree Eq Core.Utils Interp.Fold.
From ITree Require Import Basics.Basics.
From ExtLib Require Import Structures.Functor Structures.Monad.
Import ListNotations.
(* No Z scope here (measured on the first D1 build): `Require Import ZArith`
   already opens Z_scope globally, and a second `Open Scope Z_scope` inside the
   Clight window resolves the bare numerals in `SResult -> nat` positions
   (fuel arguments) against BinNums.Z - "Found a constructor of inductive type
   Z while a constructor of nat is expected".  Lower.v and the Realize fan-in
   get away without their own Z-scope line for the same reason; the
   RealizeCompose line this line originally copied opens the scope where no
   fuel-shaped argument is in range. *)
Require Import Timbda.Syntax Timbda.Semantics Timbda.Checks Timbda.Lower
  Timbda.Realize.

(* ============================================================================
   1. The target monad: a Clight accumulator the fold runs over.
   `cstate` carries the compile-side budget, the accumulated fragment, and the
   scheduler hint slot the D4 candidate-peek will fill (unused in D1 - the D1
   `g` traps - but the STATE SHAPE is ruled now so D3/D4 grow it, not replace
   it; strategy sec. 3's accumulator fields `temps`/`slots` are inert for the
   landed straight-line fragment: `lower_res`/`slot_ident` already name every
   temp the checked fragment writes, decision 10's spelling). ============================================================================ *)

Record cstate := mkCS
  { cfuel  : nat;                     (* compile-side budget, consumed per observation *)
    cfrag  : list Clight.statement;   (* the accumulated Clight fragment, in order *)
    chint  : option bool              (* D4 scheduler hint; None until the choice corner *)
  }.

Definition cstate0 (n : nat) : cstate := mkCS n nil None.

(* The algebra's three verdicts (strategy sec. 2): append-and-continue,
   emit-and-stop-unrolling (the resumption boundary as DATA - the CLoop verdict
   itself), trap (only for compilations whose C is not defined: in D1 that is
   exactly the unanswered choice). *)
Inductive CRes (X : Type) : Type :=
| CDone : list Clight.statement -> X -> CRes X
| CLoop : list Clight.statement -> CRes X
| CTrap : list Clight.statement -> CRes X.

Definition M (X : Type) : Type := cstate -> CRes X.

(* Class-supplied binders parenthesized (p529 trap: implicit binders are
   refused in Functor/Monad fields). *)
Definition retM (X : Type) (x : X) : M X := fun s => @CDone X (cfrag s) x.

Definition bindM (X Y : Type) (m : M X) (k : X -> M Y) : M Y :=
  fun s => match m s with
           | @CDone  _ l x => k x (mkCS (cfuel s) l (chint s))
           | @CLoop  _ l   => @CLoop Y l
           | @CTrap  _ l   => @CTrap Y l
           end.

Definition fmapM (X Y : Type) (f : X -> Y) (m : M X) : M Y :=
  fun s => match m s with
           | @CDone  _ l x => @CDone Y l (f x)
           | @CLoop  _ l   => @CLoop Y l
           | @CTrap  _ l   => @CTrap Y l
           end.

#[global] Instance Functor_M : Functor M := { fmap := fmapM }.
#[global] Instance Monad_M  : Monad  M := { ret := retM; bind := bindM }.

(* The target supplies `iter` (p529 verdict: this is where the budget lives;
   FoldStateT's transformer `iter` encodes no resumption policy - do not build
   on it).  D1 shape: the step function appends NOTHING (the D1 arms - h empty,
   g trap, mstep/mstuck append-free - make this a fact, lemma
   `iterF_appends_nothing` below), and the exhausted budget yields the `CLoop`
   verdict with no appended construct: the compile-fuel artifact IS the verdict
   (header: two stucks).  Field order {R I} per ITree/Basics/Basics.v:92-93. *)
(* Fix measured on the first D1 build (the trap, restated for the next reader):
   the compcert import window (`Integers`/`Values`) leaves a Z-flavored numeral
   scope in effect, so every bare nat literal in this file resolves to `Z0` -
   including `iterF`'s `0` PATTERN against `n : nat` ("Found a constructor of
   inductive type Z while a constructor of nat is expected"; patterns are not
   type-directed, and the Realize family never sees this because it has no bare
   nat literals).  Nat literals here are qualified (`Datatypes.O`) or scoped
   (`%nat`). *)
Fixpoint iterF (I R : Type) (f : I -> M (I + R)) (n : nat) (i : I) (s : cstate) : CRes R :=
  match n with
  | Datatypes.O => @CLoop R (cfrag s)
  | Datatypes.S n' =>
      match f i s with
      | @CDone  _ l (inl i') => @iterF I R f n' i' (mkCS n' l (chint s))
      | @CDone  _ l (inr r)  => @CDone R l r
      | @CLoop  _ l          => @CLoop R l
      | @CTrap  _ l          => @CTrap R l
      end
  end.

#[global] Instance MonadIter_M : MonadIter M :=
  { iter := fun R I f i s => @iterF I R f (cfuel s) i s }.

(* Kernel trees over `void1` never expose `StepF`, and the checked fragment
   never exposes `StuckF`: mstep/mstuck exist only because `fold`'s dictionary
   demands them; both spellings append nothing. *)
#[global] Instance MonadStep_M : MonadStep M :=
  { mstep := fun s => @CDone unit (cfrag s) tt }.

#[global] Instance MonadStuck_M : MonadStuck M :=
  { mstuck := fun X => fun s => @CTrap X (cfrag s) }.

(* ============================================================================
   2. The two half-morphisms. ============================================================================ *)

(* The coalgebra side is pure: `void1` has no constructor, so h is the empty
   match (p529 trap: an empty match in term position needs BOTH `return` and
   `with`).  This is strategy sec. 3's `h : void1 ~> M := ... (kernel is pure)`
   verbatim. *)
Definition h : void1 ~> M :=
  fun (X : Type) (e : void1 X) => match e return M X with end.

(* D1's branch answer: TRAP.  Decision 15's law is that the bool at a `BrF`
   site is forced by a candidate-existence certificate ("left priority" alone
   is wrong on `Choice Fail (Ret 1)` - p529 law 3), and that certificate is the
   choice corner (D4).  Until then the leaf emits NO C for a choice program -
   the honest reading of the FoldCTree horn: a fold that resolves branches
   need not preserve weak bisimilarity, so the emitted C is only defined on
   determinate programs, and an uncertified choice IS undefined behavior of the
   compiler, not a silent pick.  `chint` is the seam D4 fills. *)
Definition g : B2 ~> M :=
  fun (X : Type) (b : B2 X) (s : cstate) =>
    match (chint s) with
    | Some b' => match b in B2 Y return CRes Y with
                 | branch2 => @CDone bool (cfrag s) b'
                 end
    | None    => match b in B2 Y return CRes Y with
                 | branch2 => @CTrap bool (cfrag s)
                 end
    end.

(* ============================================================================
   3. compile: one fold, one terminal policy. ============================================================================ *)

(* The terminal write is the ONLY construct D1 emits, and it is the landed
   `Lower.v` spelling, not a re-derivation: `Sset lower_res (vconst v)` is
   exactly the statement `lower (Ret v)` writes (Lower.v:162), evaluated by the
   already-attested `eval_vconst_val` (Realize.v increment B).  The verdicts
   without a value write - `SFail` ("fail as zero", PLAN T2: a value candidate
   of zero, so no candidate is written; p529 `b_fail`) and the kernel budget's
   `SStuck` (a result, not a rule) - terminate with `Sskip` and keep their
   meaning in the `CDone` value. *)
Definition terminal_stmt (r : SResult) : Clight.statement :=
  match r with
  | SOk v   => Clight.Sset Lower.lower_res (Lower.vconst v)
  | SFail   => Clight.Sskip
  | SStuck  => Clight.Sskip
  end.

(* The hylo (strategy sec. 3, verbatim shape): `compile` folds `denE` output
   through the algebra at one shared budget - the kernel-side fuel bounds the
   denotation, the same number seeds the accumulator's `iter` (the strategy's
   single-`fuel` spelling), and the terminal policy appends the one write from
   the observed result.  No goal in this file asks `compile` for a normal form
   of a tree (decision 14's checkable guard rail: the budget law makes the
   working set proportional to the observations the goal mentions). *)
Definition compile_h (p : Expr) (fuel : nat) (hint : option bool) : CRes SResult :=
  match fold h g (denE nil p fuel) (mkCS fuel nil hint) with
  | @CDone _ frag r => @CDone SResult (frag ++ [terminal_stmt r]) r
  | @CLoop _ frag   => @CLoop SResult frag
  | @CTrap _ frag   => @CTrap SResult frag
  end.

(* ---------- D3 (probe p530): the candidate-peek scheduler.  Measured facts
   the design must honor (docs/probes/p530/README.md):
   (1) at a RESOLVED BrF, `Some true` takes the LEFT arm, `Some false` the
       right - so a bool answer means "left" / "right" outright;
   (2) `Choice Fail (Ret 1)` answers in BOTH arms (fail-as-zero IS a value
       candidate, T2) - decision 15's genuine pair, and the certificate must
       REFUSE it, not pick;
   (3) a `CLoop` verdict on an arm means UNDECIDED (fuel too shallow), NOT
       "no candidate" - the certificate is therefore three-valued;
   (4) handing a hint to a program with TWO sites makes the SAME bool answer
       every BrF (p530-B measured it: a silent left-priority run) - so the
       single-hint certificate covers programs with EXACTLY ONE site; multi-
       site programs stay trapped until D4's materialized choice nodes;
   (5) both-arms-stuck is a VACUOUS site: both answers measured identical
       (`CDone [] SStuck`, p530-B), the arms terminate as the same SStuck
       data - picking left there is provably output-neutral. *)

Inductive arm_verdict : Type := AVVal | AVStuck | AVUndef.

(* The certificate runs the SAME compile algebra (unhinted - guarded below:
   a certified site's arms are site-free) on each arm at the program budget.
   This is the determinacy analysis decision 15's ruling licenses kernel-side;
   the guard rail still holds: no whole-program normalization, one bounded
   fold per arm. *)
Definition arm_verdict_of (e : Expr) (fuel : nat) : arm_verdict :=
  match compile_h e fuel None with
  | @CDone _ _ (SOk _) => AVVal
  | @CDone _ _ SFail   => AVVal    (* fail-as-zero IS a candidate (T2; p530 (2)) *)
  | @CDone _ _ SStuck  => AVStuck  (* stuck is NOT a candidate (p529 law 2) *)
  | @CLoop _ _         => AVUndef  (* fuel-exhausted: undecided (p530 (3)) *)
  | @CTrap _ _         => AVUndef  (* uncertified interior: undecided *)
  end.


Definition pick_site (a b : option (Expr * Expr)) : option (Expr * Expr) :=
  match a, b with
  | Some x, None => Some x
  | None, Some y => Some y
  | _, _ => None                  (* two sites anywhere: refuse *)
  end.

(* Site walker: mutual on a shared DEPTH index (the one cross-shape recursion
   Rocq's structural check accepts - it refused both the Expr/list mutual
   block and constructor-rebuilt recursive arguments; only pattern variables,
   measured).  Run at `e_fuel p` (Checks.v:616): every child's `e_fuel` is
   strictly below its parent's, so the walk at that depth sees every
   constructor - EXACT.  Shallower walks only ever return `None` earlier,
   i.e. they REFUSE certification, never grant a wrong one.
   `Some` exactly when the program carries EXACTLY ONE `Choice` site; zero
   or two+ sites both give None (p530 (4): a single hint would answer every
   BrF, giving the silent left-priority run the probe measured). *)
Fixpoint scan_sites (d : nat) (p : Expr) : option (Expr * Expr) :=
  match d with
  | Datatypes.O => None
  | Datatypes.S k =>
      match p with
      | Ret _ | Glob _ | Fail => None
      | App e1 e2 | Seq e1 e2 | Unify e1 e2 =>
          pick_site (scan_sites k e1) (scan_sites k e2)
      | TupE es => scan_sites_list k es
      | Choice e1 e2 =>
          match scan_sites k e1, scan_sites k e2 with
          | None, None => Some (e1, e2)   (* the unique site *)
          | _, _       => None            (* nested sites: refuse *)
          end
      | Block _ b => scan_sites k b
      | Iter _ b e => pick_site (scan_sites k b) (scan_sites k e)
      end
  end
with scan_sites_list (d : nat) (es : list Expr) : option (Expr * Expr) :=
  match d with
  | Datatypes.O => None
  | Datatypes.S k =>
      match es with
      | nil => None
      | e :: rest => pick_site (scan_sites k e) (scan_sites_list k rest)
      end
  end.

Definition one_choice_site (p : Expr) : option (Expr * Expr) :=
  scan_sites (e_fuel p) p.

(* What the peek can decide (decision 17's three rulings + D4a's fourth): *)
Inductive peek : Type := Trap | Forced : bool -> peek | Pair.

Definition arm_certify (e1 e2 : Expr) (fuel : nat)
    (pair_at_root : bool) : peek :=
  match arm_verdict_of e1 fuel, arm_verdict_of e2 fuel with
  | AVVal, AVStuck   => Forced true    (* left arm has the candidate (p530 (1)) *)
  | AVStuck, AVVal   => Forced false   (* right arm *)
  | AVStuck, AVStuck => Forced true    (* vacuous: output-neutral (p530 (5)) *)
  | AVVal, AVVal     => if pair_at_root then Pair else Trap
                        (* THE GENUINE PAIR (decision 15: no forcing bool exists).  At the
                           ROOT the program IS the site: the node's leftmost candidate is
                           the whole observation (arbiter spec).  Under a CONTEXT the
                           pair_at_root=false arm TRAPS - measured (docs/probes/p531/):
                           a node emitted by the whole-program dispatch loses the context's
                           terminal rule (Seq-prefix `SFail`/`SOk 7`, TupE tuple-building),
                           contradicting the kernel verdict.  The trap mis-emits nothing;
                           context-carried nodes (node emission INSIDE the fold, where the
                           continuation decides the terminal) are named D4-follow-up/M3
                           obligations. *)
  | _, _             => Trap           (* an UNDECIDED side (p530 (3)) *)
  end.

Definition peek_result (p : Expr) (fuel : nat) : peek :=
  match one_choice_site p with
  | None => Trap
  | Some (e1, e2) =>
      match p with
      | Choice _ _ => arm_certify e1 e2 fuel true
      | _          => arm_certify e1 e2 fuel false
      end
  end.

(* D4a: the materialized choice node (strategy sec. 4 verbatim regime).  The
   genuine pair gets NO silent pick and no trap - the emitted C shows BOTH
   candidates and the named arbiter:

     Sset cand0 v1 ; Sset cand1 v2 ; Scall arbiter (cand0, cand1)

   ARBITER SPEC (this is the M2 pin; the implementation lands M4/M5 as the
   semantic runtime layer decision 15 named):  `arbiter` is a declared
   external reading the candidate slots; its specification is the VC-printed
   leftmost order - the `one`/`if` reading of the paper's combs: the leftmost
   candidate present IS the observed value, written to `lower_res`.  In M2 the
   arbiter is structure only: the node's Coq-side CompCert execution needs the
   extern entered into `ge0` and the candidate temps in the temp env - the
   golden test observes the node through clang (D4b), and the Coq-side exec
   lemma is recorded M4 debt, same drawer as the D1 trap's replacement.

   D4a scope (measured, not assumed): the materializable pair is BOTH ARMS
   ENDING IN A VALUE WRITE (`AVSOk` below).  A `Fail` arm ends in `Sskip` - no
   constant to put in a candidate slot - so `Choice Fail (Ret 1)` stays TRAPPED
   at D4a: it remains decision 15's genuine-pair witness (sec. 8's
   `c_choice_traps` pin stands, proof untouched), and its materialization
   waits for the fail-as-CARrier ruling (named obligation, M3+).

   The arbiter call is statement-level `Scall` (Clight has no call EXPRESSION -
   measured: `Clight.Scall : option ident -> expr -> list expr -> stmt`); the
   candidate temps are fresh positive-binary idents beside `lower_res = xH`
   (Lower.v:85), which the D4b printer maps to the harness globals. *)

Definition choice_cand0 : AST.ident := xO xH.        (* positive 2 *)
Definition choice_cand1 : AST.ident := xI xH.        (* positive 3 *)
Definition choice_arbiter : AST.ident := xO (xO xH). (* positive 4 *)

(* The value-carrying arm test: a materializable arm must end `CDone ... (SOk v)`. *)
Definition arm_sok_of (e : Expr) (fuel : nat) : option Val :=
  match compile_h e fuel None with
  | @CDone _ _ (SOk v) => Some v
  | _ => None
  end.

Definition choice_cand_stmt (id : AST.ident) (v : Val) : Clight.statement :=
  Clight.Sset id (Lower.vconst v).

Definition arbiter_signature : Ctypes.type :=
  Tfunction [Lower.tint64; Lower.tint64] Tvoid (mkcallconv None false false).

Definition pair_frag (v1 v2 : Val) : list Clight.statement :=
  [choice_cand_stmt choice_cand0 v1;
   choice_cand_stmt choice_cand1 v2;
   Clight.Scall None (Clight.Evar choice_arbiter arbiter_signature)
     [Clight.Evar choice_cand0 Lower.tint64; Clight.Evar choice_cand1 Lower.tint64]].

(* The materialization itself, citable apart from the dispatch. *)
Definition pair_result (p : Expr) (fuel : nat) : CRes SResult :=
  match one_choice_site p with
  | Some (e1, e2) =>
      match arm_sok_of e1 fuel, arm_sok_of e2 fuel with
      | Some v1, Some v2 =>
          (* leftmost IS the spec's observed value (arbiter spec above) *)
          @CDone SResult (pair_frag v1 v2) (SOk v1)
      | _, _ => @CTrap SResult nil  (* cannot happen at `Pair` (AVVal both),
                                       kept honest: the trap, never a guess *)
      end
  | None => @CTrap SResult nil      (* unreachable: `Pair` implies a site *)
  end.

Definition compile (p : Expr) (fuel : nat) : CRes SResult :=
  match peek_result p fuel with
  | Forced hint => compile_h p fuel (Some hint)
  | Trap => compile_h p fuel None
  | Pair => pair_result p fuel
  end.

(* ============================================================================
   4. The budget law, first-class so a lane can cite it (strategy sec. 5:
   "fragment length <= fuel by construction (a two-line induction on iterF,
   which I'd make a first-class lemma precisely so it can be cited when a lane
   starts costing too much)").  D1's exact statement is even smaller than the
   strategy's bound: the D1 algebra appends NOTHING during unrolling - every
   arm `fold`'s step function can take through this target (retM, fmapM over
   the hint `g`, mstep, mstuck) carries the state's fragment unchanged.

   How this proof had to be written, measured on the first D1 builds (each is
   the budget law teaching itself):
   (a) The first draft quantified the lemma over an ARBITRARY step function and
   was false - an arbitrary algebra may append; the stability fact belongs to
   THIS algebra (`h` empty, `g` the hint-trap), exactly as stated.
   (b) `fold h g t s` mentions no fuel: the budget rides in the state (`iter`
   resolves to the target's `iterF` at `cfuel s`), so an induction on a
   `fold`-headed goal yields no IH, and Rocq 9.1.1 will not unfold the
   class-resolved `iter` for you (`unfold iter`, `cbn [iter]` both fail -
   "Cannot find a relation to rewrite").  The induction therefore runs on the
   target's own `iterF` applied to an explicit step mirror `cstep`;
   `fold_bridge` pins the mirror to the library `fold` at pure convertibility
   (`reflexivity`), which is the point: a mirror that drifted from
   Interp/Fold.v:35-43 would make the pin fail.
   (c) Neither cbn nor cbv can peel the step goal: cbn's delta policy refuses
   unfoldings that land on a stuck match (`cbn [cstep]` never even exposes
   `observe t` to `destruct`), and cbv expands everything whitelisted -
   including the recursive call - leaving a raw fix and an inlined step
   function with no occurrence the IH could apply at.  The peel is two Leibniz
   lemmas, `iterF_S` and `cstep_observe`, REWRITTEN into the goal: rewriting
   fires only at the applied occurrence, so the recursive call's bare `cstep`
   argument survives intact in the library spelling the IH consumes.
   (d) `t` and `s` must be generalized BEFORE the induction (an IH formed
   after `induction fuel` is already pinned to the original tree and state),
   and the conclusion states the fragment against a named `acc` instead of
   `cfrag s`: with `cfrag s` in the conclusion, the match unifier binds the
   IH's state metavariable from the ARMS (`cfrag ?s` vs `cfrag s` decomposes
   to `?s := s`) before the scrutinee can force the `mkCS` update, and the
   unification dies on "s vs record".  With `acc` the arms carry no metavariable
   clash, and the discharged side condition `cfrag (mkCS ...) = acc` is just
   the IH hypothesis after one projection step.
   (e) `B2`'s single constructor is `branch2 : B2 bool` (CTree/Core/Index.v:19):
   a branch is always answered in `bool`, but the goal keeps it as the partial
   application `g X c`, and `(g X c) s` is not a subterm - the BrF arm needs
   `destruct c` (the index refinement) plus the pin `fmap_g_answer` before
   `chint s` can be case-split. ============================================================ *)

(* The mirror of `fold`'s step function (Interp/Fold.v:35-43), spelled in the
   constructor order `fold` matches on: RetF / StuckF / StepF / GuardF / VisF /
   BrF per CTreeDefinitions.v.  `void1`'s VisF arm and the hintless BrF arm are
   where `h`'s empty match and the trap live. *)
Definition cstep (u : ctree void1 B2 SResult) : M (ctree void1 B2 SResult + SResult) :=
  match observe u with
  | RetF r => ret (inr r)
  | StuckF => mstuck _
  | StepF u1 => fmap (fun _ : unit => inl u1) mstep
  | GuardF u1 => ret (inl u1)
  | @VisF _ _ _ _ X e k => fmap (fun x : X => inl (k x)) (h _ e)
  | @BrF _ _ _ _ X c k => fmap (fun x : X => inl (k x)) (g _ c)
  end.

(* The sanity pin: the library fold IS this target's `iterF` over `cstep`, with
   the budget taken from the state.  It proves by pure conversion - that is the
   claim: a mirror that drifted from the library would make this fail. *)
Lemma fold_bridge : forall (t : ctree void1 B2 SResult) (s : cstate),
  fold h g t s = @iterF (ctree void1 B2 SResult) SResult cstep (cfuel s) t s.
Proof. intros t s. reflexivity. Qed.

(* The peel lemmas: each an iota step of `iterF` / one delta step of `cstep`,
   stated as Leibniz equalities (each closes by `reflexivity`).  They exist so
   the induction below peels by REWRITING - which (i) does not care whether the
   unfolding "would reduce" (cbn's veto, fact (c) above) and (ii) rewrites only
   the applied occurrence, keeping the recursive call `@iterF ... cstep ...` in
   the library spelling the IH consumes. *)
Lemma iterF_S : forall (f : ctree void1 B2 SResult -> M (ctree void1 B2 SResult + SResult))
    (k : nat) (i : ctree void1 B2 SResult) (s : cstate),
  @iterF (ctree void1 B2 SResult) SResult f (Datatypes.S k) i s
  = match f i s with
    | @CDone _ l (inl i') =>
        @iterF (ctree void1 B2 SResult) SResult f k i' (mkCS k l (chint s))
    | @CDone _ l (inr r) => @CDone SResult l r
    | @CLoop _ l => @CLoop SResult l
    | @CTrap _ l => @CTrap SResult l
    end.
Proof. reflexivity. Qed.

Lemma cstep_observe : forall (t : ctree void1 B2 SResult) (s : cstate),
  cstep t s
  = (match observe t return M (ctree void1 B2 SResult + SResult) with
     | RetF r => ret (inr r)
     | StuckF => mstuck _
     | StepF u1 => fmap (fun _ : unit => inl u1) mstep
     | GuardF u1 => ret (inl u1)
     | @VisF _ _ _ _ X e k => fmap (fun x : X => inl (k x)) (h _ e)
     | @BrF _ _ _ _ X c k => fmap (fun x : X => inl (k x)) (g _ c)
     end) s.
Proof. reflexivity. Qed.

(* One BrF-specific pin.  `B2` has a single constructor, `branch2 : B2 bool`
   (CTree/Core/Index.v:19), so a tree's branch is always answered in `bool`,
   but the goal holds it as the PARTIAL application `g X c` fed into fmap -
   `(g X c) s` is not a subterm, so `destruct (g _ c s)` has nothing to catch.
   The pin evaluates the whole partial application at `s` as one Leibniz step
   cbv-expands the composition, `destruct (chint s)` substitutes at BOTH
   sides' visible scrutinees, and both reduce to the same arms.  (A bare
   `reflexivity` fails here: after delta the left is the NESTED match
   `match (match chint s with ...) with ... end`, and Coq does not convert a
   nested match to a flattened one - distribution needs the case split.) *)
Lemma fmap_g_answer : forall (k0 : bool -> ctree void1 B2 SResult) (s : cstate),
  (fmap (fun x : bool => inl (k0 x)) (g bool branch2)) s
  = match chint s with
    | Some ans => @CDone (ctree void1 B2 SResult + SResult) (cfrag s) (inl (k0 ans))
    | None => @CTrap (ctree void1 B2 SResult + SResult) (cfrag s)
    end.
Proof.
  intros k0 s. cbv [fmap g Functor_M fmapM]. destruct (chint s); reflexivity.
Qed.

(* The stability law, with the fragment compared to a named accumulator `acc`
   (fact (d) above: this is what makes the recursive `apply IH` unify at all). *)
Lemma iterF_frag_stable :
  forall (fuel : nat) (t : ctree void1 B2 SResult) (s : cstate)
    (acc : list Clight.statement),
  cfrag s = acc ->
  match @iterF (ctree void1 B2 SResult) SResult cstep fuel t s with
  | @CDone _ l _ => l = acc
  | @CLoop _ l   => l = acc
  | @CTrap _ l   => l = acc
  end.
Proof.
  intros fuel. induction fuel as [| k IH].
  - intros t s acc H. cbn [iterF]. exact H.
  - intros t s acc H. rewrite iterF_S, cstep_observe.
    (* Peel one observation, exactly as `fold` does. *)
    destruct (observe t).
    + (* RetF: `ret (inr r)` - retM appends nothing; the whole verdict
         converts to `cfrag s = acc`, which IS the hypothesis. *)
      exact H.
    + (* StuckF: `mstuck _` appends nothing. *)
      exact H.
    + (* StepF: `fmap _ mstep` - mstep appends nothing; the residual re-enters
         iterF with the same fragment, so the IH hypothesis is H up to one
         projection step (cfrag of mkCS reduces). *)
      apply IH. cbn [cfrag]. exact H.
    + (* GuardF: `ret (inl u1)` - the residual re-enters, fragment unchanged. *)
      apply IH. cbn [cfrag]. exact H.
    + (* VisF: `void1` has no constructor - `h`'s empty match closes the arm. *)
      destruct e.
    + (* BrF: `fmap (inl o) (g _ c)`.  `destruct c` is the index refinement
         `branch2 : B2 bool` (fact (e) above); then `fmap_g_answer` evaluates
         the partial application at `s`, so `destruct (chint s)` sees its own
         scrutinee.  The trapped answer converts to `cfrag s = acc` (the
         hypothesis, no recursion); the hinted answer re-enters with the
         fragment unchanged. *)
      destruct c; rewrite fmap_g_answer.
      destruct (chint s); first [ (apply IH; cbn [cfrag]; exact H) | exact H ].
Qed.

(* The fold-side corollary at the initial state: before the single terminal
   append, the accumulated fragment is EMPTY. *)
Lemma c_frag_of_fold : forall (p : Expr) (fuel : nat) (hint : option bool),
  match fold h g (denE nil p fuel) (mkCS fuel nil hint) with
  | @CDone _ frag _ => frag = @nil Clight.statement
  | @CLoop _ frag   => frag = @nil Clight.statement
  | @CTrap _ frag   => frag = @nil Clight.statement
  end.
Proof.
  intros p fuel hint. rewrite fold_bridge.
  apply iterF_frag_stable.
  cbn [cfrag]. reflexivity.
Qed.

(* Consuming the verdict: an empty pre-terminal fragment means a `CDone`
   fragment is EXACTLY the one terminal write and a `CLoop`/`CTrap` fragment is
   empty.  The hypothesis states stability for the fold verdict, the conclusion
   for the verdict AFTER the terminal append (the `compile` arm spelling), so
   the lane lemma below never destructs a fuel-stuck fold term. *)
Lemma frag_bound_of_verdict : forall (v : CRes SResult),
  (match v with
   | @CDone _ frag _ => frag = @nil Clight.statement
   | @CLoop _ frag   => frag = @nil Clight.statement
   | @CTrap _ frag   => frag = @nil Clight.statement
   end) ->
  match (match v with
         | @CDone _ frag r => @CDone SResult (frag ++ [terminal_stmt r]) r
         | @CLoop _ frag   => @CLoop SResult frag
         | @CTrap _ frag   => @CTrap SResult frag
         end) with
  | @CDone _ l _ => Datatypes.length l = 1%nat \/ Datatypes.length l = 3%nat
  | @CLoop _ l   => Datatypes.length l = 0%nat
  | @CTrap _ l   => Datatypes.length l = 0%nat
  end.
Proof.
  intros v Hr.
  destruct v as [frag r | frag | frag];
    cbn [Datatypes.length Datatypes.app] in Hr |- *.
  - left; rewrite Hr. reflexivity.
  - rewrite Hr. reflexivity.
  - rewrite Hr. reflexivity.
Qed.

(* The citable budget law.  D1-D3 form (exact 1 / 0) still holds VERBATIM on
    every `compile_h` path - choice-free, certified, vacuous, trapped; that is
    what the fold induction proves.  D4a adds the `Pair` materialization,
    which appends its node OUTSIDE any fold (two bounded arm folds plus static
    structure): with the peek's exactly-one-site scope a program can hold at
    most ONE pair node, so the citable statement becomes the disjunction
    below - 1 (straight-line terminal write) or 3 (two candidate writes + the
    arbiter call), and 0 for the no-emit verdicts.  Strategy sec. 5's general
    bound - linear in the program plus ONE node per indeterminate observer -
    is what this instantiates; multi-observer programs are D4b/M3 territory
    where the disjunction becomes a counted sum. *)

Lemma c_compile_frag_bound : forall (p : Expr) (fuel : nat),
  match compile p fuel with
  | @CDone _ l _ => Datatypes.length l = 1%nat \/ Datatypes.length l = 3%nat
  | @CLoop _ l   => Datatypes.length l = 0%nat
  | @CTrap _ l   => Datatypes.length l = 0%nat
  end.
Proof.
  intros p fuel. unfold compile.
  destruct (peek_result p fuel).
  - (* Trap: the D3 chain, verbatim. *)
    apply frag_bound_of_verdict. apply c_frag_of_fold.
  - (* Forced: the D3 chain, verbatim. *)
    apply frag_bound_of_verdict. apply c_frag_of_fold.
  - (* Pair: static structure, no fold in the fragment's accounting.  The
       node's length is pinned once (Hlen); every shape of the materialization
       decision - site present or not, each arm a value or not - closes on it
       or on `length nil = 0`. *)
    assert (Hlen : forall (v1 v2 : Val),
      Datatypes.length (pair_frag v1 v2) = 3%nat).
    { intros v1 v2. cbn [pair_frag Datatypes.length Datatypes.app]. reflexivity. }
    unfold pair_result.
    destruct (one_choice_site p) as [[e1 e2] |].
    + destruct (arm_sok_of e1 fuel) as [v1 |].
      * destruct (arm_sok_of e2 fuel) as [v2 |].
        { right. rewrite Hlen. reflexivity. }
        { cbn [Datatypes.length Datatypes.app]. reflexivity. }
      * cbn [Datatypes.length Datatypes.app]. reflexivity.
    + cbn [Datatypes.length Datatypes.app]. reflexivity.
Qed.

(* ============================================================================
   5. Corner 1 (strategy sec. 8): Ret / Fail / Seq, at Leibniz `=`, `reflexivity`
   only - the p529 specimens lifted onto the Clight accumulator, with the
   terminal write appended.  Corner names carry the p529 lineage. ============================================================================ *)

(* Arm `Ret`: one `RetF` observation, the value is `SOk v`, the fragment is the
   terminal write at the landed `vconst` spelling (p529 `b_ret`, plus terminal). *)
Lemma c_ret :
  compile (Ret (VInt 3)) 1%nat
  = @CDone SResult [Clight.Sset Lower.lower_res (Lower.vconst (VInt 3))] (SOk (VInt 3)).
Proof. reflexivity. Qed.

(* Arm `Fail`: fail as zero (p529 `b_fail`) - a result, so no trap, and no
   candidate to write. *)
Lemma c_fail :
  compile Fail 1%nat = @CDone SResult [Clight.Sskip] SFail.
Proof. reflexivity. Qed.

(* Arm `Seq`: the `>>=` spine collapses inside `observe` (p529 law 4; `b_seq`
   compiled at zero emitted cost) - one observation, one terminal write, and it
   is the SECOND value, because the kernel's `Seq` arm discards the prefix's
   (Semantics.v:219-224; the very shape T5's lemmas license reordering
   around). *)
Lemma c_seq :
  compile (Seq (Ret (VInt 1)) (Ret (VInt 2))) 2%nat
  = @CDone SResult [Clight.Sset Lower.lower_res (Lower.vconst (VInt 2))] (SOk (VInt 2)).
Proof. reflexivity. Qed.

(* The two-stucks guard, leaf-side (p529 keeps these adjacent for exactly this
   reason).  Kernel fuel exhaustion is DATA: a four-deep `Seq` at fuel 3 spends
   the kernel budget one unit per nesting layer (Semantics.v:127, decision 2),
   the innermost `Ret` meets `denE rho e 0 = sret SStuck`, the stuck value
   propagates through the bind spine, and the compile carries it as a `CDone` -
   `Sskip` terminal (nothing to write), NO loop-shaped verdict. *)
Definition e_nest4 : Expr :=
  Seq (Seq (Seq (Ret (VInt 1)) (Ret (VInt 2))) (Ret (VInt 3))) (Ret (VInt 4)).

Lemma c_kernel_fuel_nest :
  compile e_nest4 3%nat = @CDone SResult [Clight.Sskip] SStuck.
Proof. reflexivity. Qed.

(* Compile fuel exhaustion is the VERDICT: `iter` cannot ask for the next
   observation, so `compile` stops at `CLoop` with an empty fragment and no
   terminal write - and this holds even for the simplest program, because the
   compile-side budget is about OBSERVATIONS, not about the program. *)
Lemma c_compile_fuel :
  compile (Ret (VInt 3)) 0%nat = @CLoop SResult nil.
Proof. reflexivity. Qed.

(* The D1 negative corner: an uncertified choice has no defined emitted C
   (header section 2).  `denE` maps `Choice` to `br2` (Semantics.v:217), the
   fold exposes `BrF`, D1's `g` traps with the fragment untouched.  This is the
   corner D4 replaces with the candidate-peek scheduler - pinned now so the
   replacement is a measured delta, not a silent change. *)
Lemma c_choice_traps :
  compile (Choice (Ret (VInt 1)) Fail) 2%nat = @CTrap SResult nil.
Proof. reflexivity. Qed.

(* ============================================================================
   6. Gluing to the landed estate: the terminal write EXECUTES to the kernel
   value, and it does so through the already-gate-attested lemmas only -
   `eval_vconst_val` (Realize.v:404) and `exec_Sset`.  This is the per-arm
   instance of strategy sec. 6's chain link 1 (the simulation, in its D1 form:
   the observation trace is one `RetF`, the statement trace is one `exec_Sset`
   derivation); the general `Compile_Sim` grows with the corners, and this
   lemma is the shape every corner instance slots into.  Stated for every
   value, not for a corner: the lemma is one line because the lowering is
   already attested. *)

Lemma c_terminal_exec : forall (v : Val),
  Clight1.exec_stmt Realize.ge0 Clight.empty_env Realize.le0 Mem.empty
    (terminal_stmt (SOk v)) Events.E0
    (PTree.set Lower.lower_res (Realize.clight_of_val v) Realize.le0)
    Mem.empty ClightBigstep.Out_normal.
Proof.
  intros v. apply ClightBigstep.exec_Sset. apply Realize.eval_vconst_val.
Qed.

(* And the fragment `compile` pins is the fragment `lower` pins on the same
   value corner - `lower (Ret v) = Lclight (Sset lower_res (vconst v))`
   (Lower.v:162), flattened by `clight_of` (Realize.v:62).  D1's fusion reading
   in its purest specimen: the hylo and the landed lowering agree CONSTRUCT FOR
   CONSTRUCT on the value corner, at Leibniz `=`. *)
Lemma c_agrees_with_lower : forall (v : Val),
  clight_of (lower (Ret v)) = terminal_stmt (SOk v).
Proof. intros v. reflexivity. Qed.

(* ============================================================================
   7. Corner 2 (strategy sec. 8's second stop): primops through the fold -
   value-faithful straight-line, pins only.

   The corner spelling mirrors RealizeCorners.v:70's `prim_corner` (decision 5:
   `op[a1..an]` = `App (Ret (VPrim p)) (TupE (map Ret vs))`), redefined LOCAL to
   this leaf so the compile leaf never depends on a Realize-family leaf.

   Measured kernel budget (not estimated): the prim spine - `App` head, `TupE`
   argument evaluation, the prim application - spends one unit per nesting layer
   (Semantics.v:127, decision 2), and it needs FIVE: fuel 4 exhibits the stuck
   specimen, fuel 5 completes (pinned as a lemma pair below; the `Ret`/`Seq`
   corners of section 5 were 1 and 2 - prim depth is measured, like everything
   here).

   What compile EMITS for a primop: nothing but the final constant write.  The
   kernel's `prim_total` (Syntax.v:344) runs INSIDE the observation; the fold
   sees only its resulting `RetF` (p529 law 4).  Three consequences, recorded as
   pins rather than prose:

   (a) The guards are the paper's test shape (Fig. 10, lines 452-459):
       `PGt a b` success carries the LEFT operand forward (`PRes (VInt a)`),
       failure is `PFail` -> `SFail` -> `Sskip` (fail as zero).  T6's Vint-1
       guard map (`prim_guard_match_*`, RealizeCompose.v:177) is the C-side
       spelling of the SAME fact for its binop-emitting lowering; the two
       spellings agree on value and the golden test pins THIS one (strategy
       sec. 9 amendment A).
   (b) The div semantics fork (decision 11, probe p528) cannot bite here: the
       kernel value is `Z.div` - true floor, `7 / (-2) = (-7) / 2 = -4`
       (RealizeCompose's `floor_literal_*` rungs) - and compile emits NO division
       node: it writes the constant, so the emitted C executes what the kernel
       computed, by construction.  The truncating `Int64.divs` leg and its `divZ`
       ladder belong to T6's `prim_clight` binop spelling (pinned there by
       `divZ_ladder_div`), not to this algebra.
   (c) A `PStuck` prim result (the zero-divisor arm, Syntax.v:349) arrives as
       `SStuck` DATA in a `CDone` verdict - the third stuck specimen, and an
       honesty note the corpus must keep: at the verdict level prim-guard stuck
       and kernel-fuel stuck are the SAME observable shape (`CDone [Sskip]
       SStuck`); the distinction is provenance, not output.  Section 5's
       `c_kernel_fuel_nest` pins the fuel side on a division-free program.

   Every corner below satisfies the budget law (`c_compile_frag_bound`):
   exactly one write for the value corners, zero for the fail/stuck corners. *)

Definition cprim (p : Prim) (vs : list Val) : Expr :=
  App (Ret (VPrim p)) (TupE (map Ret vs)).

(* The measured minimum: spine stuck at 4, complete at 5. *)
Lemma c_prim_fuel4_stuck :
  compile (cprim PAdd [VInt 2; VInt 3]) 4%nat
  = @CDone SResult [Clight.Sskip] SStuck.
Proof. reflexivity. Qed.

Lemma c_prim_add :
  compile (cprim PAdd [VInt 2; VInt 3]) 5%nat
  = @CDone SResult [Clight.Sset Lower.lower_res (Lower.vconst (VInt 5))] (SOk (VInt 5)).
Proof. reflexivity. Qed.

(* (a) Guard success carries the left operand (Fig. 10's `gt1` witness shape). *)
Lemma c_prim_gt_left :
  compile (cprim PGt [VInt 3; VInt 2]) 5%nat
  = @CDone SResult [Clight.Sset Lower.lower_res (Lower.vconst (VInt 3))] (SOk (VInt 3)).
Proof. reflexivity. Qed.

(* (a) Guard failure is fail-as-zero: a result (not a trap), no candidate written. *)
Lemma c_prim_gt_fail :
  compile (cprim PGt [VInt 2; VInt 3]) 5%nat
  = @CDone SResult [Clight.Sskip] SFail.
Proof. reflexivity. Qed.

(* (b) The two negative quadrants of the floor ladder, as constants: the kernel
       floors (Z.div), and C never sees a division. *)
Lemma c_prim_div_floor_negq :
  compile (cprim PDiv [VInt 7; VInt (-2)]) 5%nat
  = @CDone SResult [Clight.Sset Lower.lower_res (Lower.vconst (VInt (-4)))] (SOk (VInt (-4))).
Proof. reflexivity. Qed.

Lemma c_prim_div_floor_negp :
  compile (cprim PDiv [VInt (-7); VInt 2]) 5%nat
  = @CDone SResult [Clight.Sset Lower.lower_res (Lower.vconst (VInt (-4)))] (SOk (VInt (-4))).
Proof. reflexivity. Qed.

(* (c) The prim-guard stuck: zero divisor is `PStuck` in prim_total, SStuck data
       in a CDone verdict, `Sskip` terminal - the third stuck specimen. *)
Lemma c_prim_div_zero :
  compile (cprim PDiv [VInt 1; VInt 0]) 5%nat
  = @CDone SResult [Clight.Sskip] SStuck.
Proof. reflexivity. Qed.

(* `PNEq` in both directions: equal is `PFail` (the paper's negative-guard
   polarity, Syntax.v:357), different carries the left operand. *)
Lemma c_prim_neq_equal_fail :
  compile (cprim PNEq [VInt 1; VInt 1]) 5%nat
  = @CDone SResult [Clight.Sskip] SFail.
Proof. reflexivity. Qed.

Lemma c_prim_neq_diff :
  compile (cprim PNEq [VInt 1; VInt 2]) 5%nat
  = @CDone SResult [Clight.Sset Lower.lower_res (Lower.vconst (VInt 1))] (SOk (VInt 1)).
Proof. reflexivity. Qed.

(* ============================================================================
   8. Corner 3 (strategy sec. 8's third stop): the CERTIFIED choice.  D3
   installs the candidate-peek scheduler at the `chint` seam - the certificate
   is decision 15's forcing bool, computed kernel-side by running the SAME
   compile algebra on each arm (three-valued: has-candidate / stuck /
   UNDECIDED, per p530), and everything below is a measured delta from D1's
   trap pin (`c_choice_traps`), exactly the "pinned now so the replacement is
   a measured delta" discipline.

   Ruled by the p530 measurements (docs/probes/p530/README.md):
   (1) `true` = LEFT arm, `false` = right at a resolved BrF;
   (2) genuine pairs (`Choice Fail (Ret 1)`: fail-as-zero is a candidate) stay
       TRAPPED - the certificate refuses, it does not pick;
   (3) `CLoop` on an arm is UNDECIDED, never read as "no candidate";
   (4) exactly-one-site programs get certified; multi-site programs stay
       trapped until D4 materializes choice nodes - the probe shows why a
       single hint must not be loosed there (it answers EVERY BrF: silent
       left-priority);
   (5) both-stuck sites are vacuous: both answers measured IDENTICAL, so
       certifying left there emits what either arm would.

   Fuel honesty: the certificate runs at the PROGRAM budget `fuel`; the corners
   below are shallow (arm completion well inside the budget).  p530 also
   measured the failure mode at the boundary: `Choice (Ret 1) div0` at fuel 1
   certifies left but the main fold cannot reach the BrF in time - `CLoop`,
   the budget verdict, NOT a wrong pick.  A remaining-fuel peek is D4/corpus
   work; the trap never mis-emits. ============================================================================ *)

(* (1)+(4): the determinate site - value over stuck - compiles. *)
Lemma c_choice_forced_value :
  compile (Choice (Ret (VInt 1)) (cprim PDiv [VInt 1; VInt 0])) 5%nat
  = @CDone SResult [Clight.Sset Lower.lower_res (Lower.vconst (VInt 1))] (SOk (VInt 1)).
Proof. reflexivity. Qed.

(* (1): the flip - stuck left, value right - forces the OTHER bool. *)
Lemma c_choice_forced_flip :
  compile (Choice (cprim PDiv [VInt 1; VInt 0]) (Ret (VInt 2))) 5%nat
  = @CDone SResult [Clight.Sset Lower.lower_res (Lower.vconst (VInt 2))] (SOk (VInt 2)).
Proof. reflexivity. Qed.

(* (5): the vacuous site: stuck over stuck.  Certifying left emits exactly
       what either arm would; the agreement itself is pinned next. *)
Lemma c_choice_vacuous_stuck :
  compile (Choice (cprim PDiv [VInt 1; VInt 0]) (cprim PDiv [VInt 2; VInt 0])) 5%nat
  = @CDone SResult [Clight.Sskip] SStuck.
Proof. reflexivity. Qed.

Lemma c_choice_vacuous_agrees :
  compile_h (Choice (cprim PDiv [VInt 1; VInt 0]) (cprim PDiv [VInt 2; VInt 0])) 5%nat (Some true)
  = compile_h (Choice (cprim PDiv [VInt 1; VInt 0]) (cprim PDiv [VInt 2; VInt 0])) 5%nat (Some false).
Proof. reflexivity. Qed.

(* (2): the genuine pair with a Fail arm stays TRAPPED even at D4a: peek says
       `Pair`, but the Fail arm ends `Sskip` - no constant to seat in a
       candidate slot - so section 5's `c_choice_traps` stands, proof untouched
       (the honest scope line of sec. 3's D4a block: materialization needs
       both arms ending in VALUE writes; the fail-as-carrier ruling is named
       M3+ debt). *)

(* (4): two sites refuse the single-hint certificate - the trap stands even
       though the OUTER site alone would certify. *)
Lemma c_choice_two_sites_refused :
  compile (Choice (Choice (Ret (VInt 1)) (cprim PDiv [VInt 1; VInt 0])) (Ret (VInt 2))) 5%nat
  = @CTrap SResult nil.
Proof. reflexivity. Qed.

(* Fuel honesty at the boundary: certified left, fold too shallow - the budget
   verdict `CLoop`, never a wrong pick. *)
Lemma c_choice_lowfuel_undecided :
  compile (Choice (Ret (VInt 1)) (cprim PDiv [VInt 1; VInt 0])) 1%nat
  = @CLoop SResult nil.
Proof. reflexivity. Qed.

(* The site inside a `Seq`: the certificate travels with the program - the
   single site deeper in the tree is found by the walker at `e_fuel` depth and
   certified; the discarded-prefix value rule (Semantics.v) still decides what
   the terminal write says. *)
Lemma c_choice_certified_in_seq :
  compile (Seq (Choice (Ret (VInt 1)) (cprim PDiv [VInt 1; VInt 0])) Fail) 5%nat
  = @CDone SResult [Clight.Sskip] SFail.
Proof. reflexivity. Qed.

(* ============================================================================
   9. Corner 4 (D4a): the genuine value pair MATERIALIZES a choice node.
   The strategy's regime - "candidate blocks followed by a Scall to a named
   arbiter" - at its specimen size, with the arbiter spec pinned where the
   shape is pinned (sec. 3): leftmost-candidate-present is the observed value.
   Every pin is `reflexivity` over closed terms: the emitted structure is what
   the algebra says it is, and the D1 trap pin (`c_choice_traps`) is one lemma
   away, differing exactly by the Fail-arm scope line. ============================================================================ *)

Definition c_pair_prog : Expr := Choice (Ret (VInt 1)) (Ret (VInt 2)).
Definition c_pair_flip_prog : Expr := Choice (Ret (VInt 2)) (Ret (VInt 1)).

Lemma c_pair_node_shape :
  compile c_pair_prog 5%nat
  = @CDone SResult
      [Clight.Sset choice_cand0 (Lower.vconst (VInt 1));
       Clight.Sset choice_cand1 (Lower.vconst (VInt 2));
       Clight.Scall None (Clight.Evar choice_arbiter arbiter_signature)
         [Clight.Evar choice_cand0 Lower.tint64; Clight.Evar choice_cand1 Lower.tint64]]
      (SOk (VInt 1)).
Proof. reflexivity. Qed.

(* Leftmost IS the spec's observation: flipping the arms moves the candidate
   constants AND the verdict value together - the arbiter never reorders. *)
Lemma c_pair_node_flip :
  compile c_pair_flip_prog 5%nat
  = @CDone SResult
      [Clight.Sset choice_cand0 (Lower.vconst (VInt 2));
       Clight.Sset choice_cand1 (Lower.vconst (VInt 1));
       Clight.Scall None (Clight.Evar choice_arbiter arbiter_signature)
         [Clight.Evar choice_cand0 Lower.tint64; Clight.Evar choice_cand1 Lower.tint64]]
      (SOk (VInt 2)).
Proof. reflexivity. Qed.

(* The pair path never unrolls the MAIN program (the node IS the branch's
   compilation; the two arm folds are bounded by the same `fuel`): even at
   fuel 1 - where the forced corner hit `CLoop` - the pair materializes
   complete.  Budget honesty: the arm folds are what cost; the node is O(1)
   per observer, exactly strategy sec. 5. *)
Lemma c_pair_lowfuel_materializes :
  compile c_pair_prog 1%nat
  = @CDone SResult
      [Clight.Sset choice_cand0 (Lower.vconst (VInt 1));
       Clight.Sset choice_cand1 (Lower.vconst (VInt 2));
       Clight.Scall None (Clight.Evar choice_arbiter arbiter_signature)
         [Clight.Evar choice_cand0 Lower.tint64; Clight.Evar choice_cand1 Lower.tint64]]
      (SOk (VInt 1)).
Proof. reflexivity. Qed.

(* The D3 corner menu is UNCHANGED by D4a - measured re-pins, not hope:
   forced value/stuck and the flip still fold under their cert (`c_choice_forced_*`),
   the vacuous site still agrees, the two-site program still refuses (`peek`
   says Trap before any pair question), and the Fail-arm pair still traps. *)

(* Root-scope ruling (probe p531, docs/probes/p531/): the `Pair` dispatch is a
   whole-program replacement outside the fold, so it can only see the SITE -
   under a CONTEXT it loses the context's terminal rule (p531 measured a
   `Seq _ Fail` prefix emitting the node with `SOk 1` where the kernel says
   `SFail`, a `Seq _ (Ret 7)` prefix saying `SOk 1` where the kernel says
   `SOk 7`, and a `TupE` prefix dropping its tuple-building).  The certified
   FORCED rulings need no root scope (the fold carries the context:
   `c_choice_certified_in_seq`) - only the genuine pair does.  Context-carried
   genuine pairs TRAP at D4a: the trap mis-emits nothing; node emission INSIDE
   the fold (where the continuation decides the terminal) is a named
   D4-follow-up/M3 obligation. *)
Lemma c_pair_in_seq_refused :
  compile (Seq c_pair_prog Fail) 5%nat = @CTrap SResult nil.
Proof. reflexivity. Qed.

Lemma c_pair_in_seq_val_refused :
  compile (Seq c_pair_prog (Ret (VInt 7))) 5%nat = @CTrap SResult nil.
Proof. reflexivity. Qed.

Lemma c_pair_in_tup_refused :
  compile (TupE [c_pair_prog; Ret (VInt 3)]) 5%nat = @CTrap SResult nil.
Proof. reflexivity. Qed.

Lemma c_pair_in_block_refused :
  compile (Block nil c_pair_prog) 5%nat = @CTrap SResult nil.
Proof. reflexivity. Qed.

(* The certified FORCED ruling in the same context carrier, re-pinned green:
   the hint travels with the fold, the terminal rule still decides. *)
Lemma c_pair_forced_in_seq_untouched :
  compile (Seq (Choice (Ret (VInt 1)) (cprim PDiv [VInt 1; VInt 0])) Fail) 5%nat
  = @CDone SResult [Clight.Sskip] SFail.
Proof. reflexivity. Qed.
