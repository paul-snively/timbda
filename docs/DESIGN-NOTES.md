# Timbda-0 kernel design notes

Working notes for the M0 Gallina spike (`coq/`).  These record *why* the kernel
is shaped the way it is, and the toolchain facts that the shape depends on.
Rule provenance itself lives in `docs/VERSE-RULES.md`; milestone scope in
`docs/PLAN.md`.

## 1. Locally-nameless / de Bruijn conventions

- Locals are de Bruijn **indices**, innermost binder = `0` (Weirich autosubst
  idiom: raw AST + a disciplined `lift`/`shrink`; PLAN § 5.2 "well-scoped ASTs").
- A block `block{∃X{hp}. e}` stores its slot list `X` **outermost-first**:
  slot `i` may refer to the `i` slots listed before it, so at slot `i`'s entry
  position the cutoff is `i + d` (where `d` counts binders already crossed
  *outside* the block); the body position has cutoff `|X| + d`.
- Slot values are `option Val`: `None` = declared-but-unvalued, the domain of
  the promote/Gc rules (VERSE-RULES § 2, Fig. 8).  Non-recursive slots only;
  recursive heaps are the Gc-Rec/Def-Rec Tier-2 rows.
- `liftE k e` inserts `k` binders *outside* `e`; `shrinkE e` (cutoff `d`) removes
  the binder at index `d` and reindexes above it.  Under the GC1 side condition
  (`occurs` says the dropped binder is unused) the `Var d -> Var 0` clause is
  unreachable junk.

## 2. Coq 9.1 recursive-function constraints (measured, not theorised)

Probe files: `/tmp/opencode/synprobe/p1..p15.v` (rocq 9.1.0, switch
`RP.2026.02.0~9.1~2026.01`).  Findings that shaped `coq/Syntax.v`:

| Idiom | Result on 9.1 |
|---|---|
| Mutual `Fixpoint {fV, fE}` recursing on Val/Expr structure only | accepted |
| Same block plus a **list-typed** member (`fVs : list Val -> list Val`) | **rejected** — "Cannot guess decreasing argument of fix" / "Recursive call to fa2 has principal argument equal to "v" instead of "rest"" |
| Element↔list cycles written with the accumulator idiom (`with fGo : nat -> list A -> list A := fix go ... end 0`) | **rejected** (same messages) |
| Eta self-calls inside a mutual block: `map (liftV k d) vs`, `existsb (occursE i) es` | accepted, computes correctly |
| Total walker taking an **opaque callback** (`walkSlotsV (cb : Val -> nat -> Val)`), fed `fun v i => liftV k (i + d) v` from the element block | accepted, computes correctly |
| Uniform-`nat`-fuel mutual block (fuel at argument position 1 of every member) | accepted (kept as the fallback if eta-calls ever meet a proof wall) |
| Cutoff threaded through the *returned* function (`match v return (nat -> Val) with ...`) | accepted, but list cases must then be stubbed or supplied separately |
| `Inductive PrimResult := PRes Val \| ...` (anonymous constructor parameter) | **rejected**: "Cannot infer the type of Val" — write `PRes : Val -> PrimResult` |
| `From Coq Require Import ...` | deprecated warning → use `From Stdlib` |

Chosen design (p14a, now in `coq/Syntax.v`): two total walkers defined *before*
the element blocks —

```coq
Fixpoint walkSlotsV (cb : Val -> nat -> Val) (d0 : nat)
  (slots : list (Ty * option Val)) : list (Ty * option Val) := ...
Fixpoint anySlotsV (cb : Val -> nat -> bool) (p0 : nat)
  (slots : list (Ty * option Val)) : bool := ...
```

and element-only mutual blocks `{liftV,liftE}`, `{shrinkV,shrinkE}`,
`{occursV,occursE}` whose Block cases read

```coq
Block (walkSlotsV (fun v i => liftV k (i + d) v) d slots)
      (liftE k (length slots + d) body)
```

This keeps every recursive call structurally decreasing on a Val/Expr, so no
fuel is needed anywhere in the kernel — which matters because the M0 soundness
lemmas are proved by `coinduction`/`play` over the ctrees layer, not by
induction over syntax.

## 3. ctrees / itree layer

- Vendored at `deps/ctrees` = `github:vellvm/ctrees@cabcf9bf24b0f459204a7da19ac01b7697ff04e3`
  (branch `dev`, pins.toml `[formal.ctrees]`).  Upstream package name is
  `rocq-ctree` (version `2.0-dev`), Coq logical path `CTree`; the checkout needs
  no local patches — `tools/ctrees-sync.sh` reproduces it from pins.toml.
- Import ladder used by the kernel (mirrors `deps/ctrees/examples/ImpBr/ImpBr.v`):
  `From CTree Require Import CTree Eq.` pulls `Equ`/`Trans`/`SBisim`/`SSim`/
  `CSSim` and the up-to coinduction tactics (`coinduction`, `step`, `play`,
  `upto_bind`, `upto_bind_eq`).  `Import CTreeNotations` + `Open Scope ctree_scope`.
- Pure effect signature is itree's `void1`, written directly: `ctree void1 B2 R`.
  There is no `Empty` in ctrees, and `ctree (fun _ => void1)` is the wrong shape.
- Choice is the binary-branch bifunctor `B2` (`Br`/`BrS` visible; `spin` is the
  divergent branch).  The laws the kernel's `Choice` depends on
  (`theories/Eq/SBisim.v:1315-1372`): `br2_assoc`, `br2_commut`, `br2_idem`,
  `br2_merge`, `br2_is_stuck`, `br2_stuck_l`, `br2_stuck_r`, `br2_spin_l`
  (`coq/Probe.v` exercises four of them).  `~` is SBisim; `sbisim_wbisim`
  (`theories/Eq/WBisim.v:227`) is the bridge to weak bisimilarity used by the
  strategy-freedom statements.  Stay off `brS2`.
- State handling: `interp_state` + a `E ~> Monads.stateT env (ctree void1 B2)`
  handler, and an `is_simple` instance on the effect signature so that
  `interp_state_sbisim` can transport SBisim through the interpreter.

## 4. Build / dev-shell workflow

```sh
tools/ctrees-sync.sh                                  # vendored ctrees + opam pin
cd coq && opam exec --switch RP.2026.02.0~9.1~2026.01 -- dune build
python3 tools/pins/pins.py check                      # pins.toml == MODULE.bazel == flake.lock
```

Dune facts learned the hard way (all recorded in `coq/dune-project`):

- `(lang dune 3.21)` must be the **first** line of `dune-project`.
- `(using coq 0.7)` — `0.11` breaks the `Stdlib` logical path under rocq 9.1;
  silence the resulting lint with `(warnings (deprecated_coq_lang disabled))`.
- The project name and the package name must match (`timbda-kernel`), and
  `(coq.theory (name Timbda) (package timbda-kernel))` has **no** `(deps …)`
  field: logical dependencies come from the installed libraries.
- List patterns (`[VInt a; VInt b]`) need `Import ListNotations`.

## 5. Toolchain probe results (pinned nixpkgs)

At the pinned nixpkgs
(`b349185bb79c7cf7ad8ea8c097931730bf473c71`, nixos-26.05):

- `rocqPackages.rocq-core` = `9.1.1`, `rocqPackages.stdpp` = `1.13.0`,
  `rocqPackages.relation-algebra` = `1.8.0`;
  `rocqPackages` has **no** ctrees / coinduction / coq-ext-lib / coq-itree, so
  M-2 builds those from the locked flake inputs with a local `mkRocqDerivation`
  (they already exist in the opam dev switch: `rocq-coinduction` 1.21,
  `coq-ext-lib` 0.13.0, `coq-itree` dev, `rocq-ctree` 2.0-dev pinned).
- Only the legacy `coqPackages` namespace provides `equations` (`1.3.1+9.1`).
- No ghc/cabal on PATH: the Haskell golden tests run through nix only
  (`tests/golden/run.sh`, `haskell.compiler.ghc912` = 9.12.3).

## 6. T1 proof machinery (M0, measured)

Batch probes under `/tmp/opencode` (`probes8/9/10.py`, `p11*.v`, `p12_axioms.v`); the
per-rule status table is `docs/RULES-AUDIT.md` § 1.  The findings that shaped
`coq/Denotation.v`:

- Applying a ctrees `~` (sbisim) lemma to an `≈` goal fails outright - sbisim and
  wbisim are different greatest fixed points ("gfp (sb eq) … vs gfp wb …").  Bridge
  with `sbisim_wbisim_subrelation` / `equ_wbisim_subrelation`.
- `bind` is a cofixpoint (`CTree.subst`): `bind (sret x) k = k x` is *not* provable by
  `cbv`/`reflexivity`.  Every computation lemma transports the goal to `≅` (equ),
  rewrites `bind_ret_l` there (`setoid_rewrite`), and closes with `reflexivity`.
- cbn on rocq 9: fixpoints like `negb`/`andb`/`rev`/`app`/`length` reduce **only when
  they are in the delta list**; `Z.eqb`/`Z.ltb` must stay OUT of it, otherwise the
  hypothesis-driven rewrites lose their match.  Two vocabularies: `t1_norm` (unfold
  `prim_total`) and `t1_fold` (keep `prim_total p [...]` folded for rows whose
  hypothesis is an equation about it).  Boolean hypotheses go through reflection
  lemmas (`zeqb_self_true`, `prim_total_PGt_true/_false`, `prim_total_PIsInt_fail`),
  never goal-side `inversion`.
- Ltac `;` semantics: a tactic chain terminated by `.` leaves only one live goal -
  the siblings are shelved - producing "Attempt to save an incomplete proof" / "No
  such goal".  Each row's full per-case discharge lives in ONE `;` chain (see
  `RewSound_EqK1/EqK2/EqTup2`).  Identifiers are resolved at Ltac *definition* time:
  `apply Hne` inside an Ltac body is "The reference Hne was not found"; match the
  hypothesis pattern instead.  `Show` is likewise unavailable inside Ltac bodies.
- `Print Assumptions` (build-time): every discharged `≈`-level lemma - and ctrees'
  own lemmas, e.g. `Probe.v`'s `ex_br2_commut` - prints exactly one axiom,
  `Eqdep.Eq_rect_eq.eq_rect_eq`, inherited from ctrees' Program-generated definitions;
  `closeV_lit`/`closeV_map_VInt` print "Closed under the global context".  Audit:
  `docs/RULES-AUDIT.md` § 6.
- `Stdlib.Bool`'s level-40 `&&&` notation clashes hard with the ctrees chain notation
  table (level 59): do not import Bool directly; it arrives transitively via
  `Timbda.Syntax`.
- Comment hazard: a substring like `…/Eq/*` inside a `(* … *)` header terminates the
  comment early ("illegal begin of vernac").
