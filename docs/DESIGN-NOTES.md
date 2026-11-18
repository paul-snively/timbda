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

- Pinned as `github:vellvm/ctrees@cabcf9bf24b0f459204a7da19ac01b7697ff04e3` (branch `dev`,
  pins.toml `[formal.ctrees]`).  Upstream package name is `rocq-ctree` (version `2.0-dev`),
  Coq logical path `CTree`; the flake builds it from that input (`nix build
  .#packages.x86_64-linux.timbda-ctrees`) with **no local patches**.  The same revision can be
  materialised as a read-only working copy under `deps/ctrees` via `tools/ctrees-sync.sh`, which
  is what the `deps/ctrees/theories/...` line citations below point into.
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

Toolchain contract (docs/PLAN.md § 6 "Formalization side": *Nix-native Rocq; opam
secondary*): the host provides **nix only**.  Rocq, Python 3, GHC, Bazel/bazelisk, git —
everything else — arrives from the flake; nothing else on the host is load-bearing.
Canonical loop:

```sh
python3 tools/pins/pins.py check                          # pins.toml == MODULE.bazel == flake.lock
nix build .#checks.x86_64-linux.version-consistency       # nixpkgs tool versions == pin table
nix build .#checks.x86_64-linux.coq-load-chain            # every kernel logical dep resolves on nix
nix build .#packages.x86_64-linux.timbda-kernel           # M0 kernel + its Print Assumptions audit
nix build .#checks.x86_64-linux.corpus-differential       # two-corner differential corpus (tools/corpus/README.md)
nix develop .#rocq                                        # or .#all: Rocq + GHC + bazelisk, all flake-provided
cd coq && dune build                                      # the in-shell kernel build
```

**DEV-3 closed (2026-11-18).**  `flake.nix`'s `coqStack` builds the libraries nixpkgs does not
ship — `coq-ext-lib`, `paco`, `rocq-coinduction` (tag `v1.21`), `coq-itree`, `rocq-ctree` —
from the locked flake inputs (pins.toml `[formal.*]`; each also exposed as
`nix build .#packages.x86_64-linux.timbda-{extlib,paco,coinduction,itrees,ctrees}`), and
relation-algebra / equations / Stdlib come from nixpkgs.  So `cd coq && dune build` runs inside
`nix develop .#rocq` with **nix only** on the host; the transitional switch is retired (it held
rocq-coinduction 1.21, coq-ext-lib 0.13.0, coq-itree dev@284d4224, coq-paco dev@d0561bf,
rocq-ctree 2.0-dev, dune 3.21.0 — all now reproduced by the flake from the pin table).
Verified 2026-11-18 on the pinned toolchain: kernel build clean (8 `.vo` modules, 12m58s),
load-chain clean, version-consistency clean, golden-test clean.

The kernel build *is* the axiom gate: `timbda-kernel`'s `buildPhase` fails if `Admitted`
appears in dune's output, or if the `Print Assumptions` blocks (§ 6, RULES-AUDIT § 6) name
anything other than exactly one axiom, `Eqdep.Eq_rect_eq.eq_rect_eq`.

`tools/ctrees-sync.sh` survives only as a way to read the pinned ctrees source locally (the
notes above quote `deps/ctrees/theories/...` line anchors); its opam-switch pinning mode is
removed, and CTree reaches the build through the flake input instead.

Dune facts learned the hard way (all recorded in `coq/dune-project`):

- `(lang dune 3.21)` must be the **first** line of `dune-project`.
- `(using coq 0.7)` is load-bearing, not taste.  coq lang ≥ 0.8 makes dune compile with
  `coqc -boot`, and `-boot` switches off rocq 9.1's implicit loadpath: because nixpkgs ships
  the Stdlib as a *package* (`rocqPackages.stdlib` → `user-contrib/Stdlib`) rather than as
  rocq-core theories, `From Stdlib Require …` and bare `ZArith`/`BinPos` then fail — that was
  every 0.8-mode failure measured in extlib/ctrees on 2026-11-18.  coq lang 0.7 is dune's
  "implicit bootstrap": no `-boot`, rocq keeps its loadpath.  `(using rocq 0.11)` (the new RBL)
  is not an option yet: dune's rocq mode needs the RBL-era package layout nixpkgs' 9.1 doesn't ship.
- coq lang 0.7 also **rejects** installed theories in `(theories CTree …)` ("Theory CTree not
  found in the current scope. Upgrade to coq lang 0.8"), which is why `coq/dune` carries no
  `(theories …)`/`(deps …)`: logical deps resolve through rocq's loadpath.  nixpkgs' rocq hook
  exports ROCQPATH only, dune 3.21's coq-mode theory DB scans COQPATH only, so the flake mirrors
  one into the other (its own `setupHook` + `export COQPATH="$ROCQPATH…"` in each buildPhase).
- dune's coq mode calls `coqc`/`coqdep`/`coqdoc`; nixpkgs' rocq 9.1 ships only `rocq`, so
  `flake.nix` provides `rocq-shims` (`rocq c` / `rocq dep` / `rocq doc`).
- silence the deprecated-coq-lang lint with `(warnings (deprecated_coq_lang disabled))`.
- The project name and the package name must match (`timbda-kernel`), and
  `(coq.theory (name Timbda) (package timbda-kernel))` has **no** `(deps …)`
  field: logical dependencies come from the installed libraries.
- List patterns (`[VInt a; VInt b]`) need `Import ListNotations`.

## 5. Toolchain probe results (pinned nixpkgs)

At the pinned nixpkgs
(`b349185bb79c7cf7ad8ea8c097931730bf473c71`, nixos-26.05):

- `rocqPackages.rocq-core` = `9.1.1`, `rocqPackages.stdpp` = `1.13.0`,
  `rocqPackages.relation-algebra` = `1.8.0`;
  `rocqPackages` has **no** ctrees / coinduction / coq-ext-lib / coq-itree / paco, so
  `flake.nix`'s `coqStack` builds them from the locked inputs (all built clean 2026-11-18:
  `coq-ext-lib` 0.13.0-dev, `coq-paco` 4.4-dev, `rocq-coinduction` 1.21, `coq-itree`
  5.2.1-dev, `rocq-ctree` 2.0-dev).  Two pins moved to get there: coinduction master needs
  rocq ≥ 9.2 (retargeted to tag `v1.21`), and interaction-trees needs `Paco.paco`
  (`[formal.paco]` added) — see the pins.toml notes.
- Two upstream build quirks needed patching: extlib's `dune-project` says `using coq 0.8`
  (retargeted to 0.7 by `postPatch`), and paco's `src/Makefile` still invokes the retired
  `coq_makefile` binary (`rocq makefile -f`).
- Only the legacy `coqPackages` namespace provides `equations` (`1.3.1+9.1`).
- Coinduction ships a findlib plugin (`lib/ocaml/4.14.4/site-lib/rocq-coinduction/plugin.cmxs`),
  loaded by `From Coinduction Require Import all`; findlib's hook puts it on OCAMLPATH.  Outside a
  derivation (`nix shell`) no setup hooks run, so ROCQPATH/COQPATH/OCAMLPATH have to be set by hand.
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
- The lazy-and notation is owned twice: `Stdlib/Bool/Bool.v:919-920` declares
  `a &&& b` (left assoc) at **level 40** in `lazy_bool_scope`, and
  `RelationAlgebra/common.v:28` declares `a &&& b` (right assoc) at **level 59**.
  Loading both in one compilation unit is a hard load-time error in either order; the
  ctrees side arrives through `CTree/Eq/WBisim.v:55-56`
  (`From RelationAlgebra Require Export rel srel monoid kat kat_tac rewriting
  normalisation`) → `monoid.v:6` `Require Export lattice` → `lattice.v` imports
  `common`.  Rule and probes: § 7.3.
- Comment hazard: a substring like `…/Eq/*` inside a `(* … *)` header terminates the
  comment early ("illegal begin of vernac").

## 7. Candidate sets: br2/`≈`, not stdpp `gset` (measured 2026-11-18)

`docs/PLAN.md` § 5 once said candidate sets would be "stdpp `gset`s".  Measured against
the pinned toolchain (rocq-core 9.1.1, stdpp 1.13.0, Stdlib 9.0.0, relation-algebra
1.8.0, ctrees 2.0-dev; nixpkgs `b349185bb79c7cf7ad8ea8c097931730bf473c71`; kernel
`/nix/store/llqcq9lhppbnkdm4xmxlkap02xsfwn8v-timbda-kernel-0.1.0`) that carrier is not
available at the cost PLAN implied.  Probes: `/tmp/opencode/stdpp-probe` (`nix build
--no-link .#probe-*`, reports at `$out/gX-report.txt`).

### 7.1 What a `gset` carrier would need

| Probe | Configuration | Measured result |
|---|---|---|
| gA1 | `From stdpp Require Import base sets gmap countable.`; carrier `gset nat` (`list_to_set [1; 2; 2]`); AC/unit laws stated up to `≡`, closed by `set_solver` | 5/5 closed |
| gA2 | same carrier, AC laws stated as Leibniz equalities (`=`) over `gset nat` - the shape a `T8`-style candidate-bag lemma wants; closed via `gset_leibniz` (`gmap.v:639`) / `set_eq` (`sets.v:571`) + `elem_of_union`, or `set_solver` | 4/4 closed.  So Leibniz *is* available for `gset` - the gate is `Countable`, not the equality |
| gB1 | `coq/Syntax.v`'s AST pasted verbatim (`ident := positive`, mutual `Val`/`Expr`, `SResult`), then `Goal Countable SResult. Proof. apply _. Qed.` | **`Error: Could not find an instance for "EqDecision SResult"`** – `gset K = mapset (gmap K)` (`gmap.v:599`) requires `Countable K`, and `Countable` carries `EqDecision` (`countable.v:12-16`).  `SResult`/`Val`/`Expr` are mutually recursive with `Z`, `positive`, `list` and binder-bearing ctors (`VLam Ty Expr`), so both `EqDecision` and `Countable` must be hand-written; there is no stock instance |
| gB2 | same AST, carrier `listset SResult` (`Listset [SOk (VInt 1); SFail; SStuck]`) - no `Countable` needed | 5/5 closed up to `≡` – but see gC2 |
| gC | `listset Outcome` (`Record Outcome := MkOutcome { outcome_of : option (option Z) }`); AC laws via the `IdemP`/`Comm`/`Assoc` `SemiSet` instances `listset.v` provides | 4/4 closed |
| gC2 | `listset Outcome` Leibniz attempt: `x ∪ y = y ∪ x` via `unfold_leibniz; apply (comm _)` | **fails**: `Error: Could not find an instance for "Comm eq union"`.  `listset` (`listset.v:6`, a `Record` over `list` with `SemiSet` instances only, `base.v:1536`/`1546`) has no `LeibnizEquiv` instance, so the Leibniz-gated `union_*_L` laws (`sets.v:590-598`) do not apply: `listset` only speaks up to `≡` (setoid), not up to `=` |
| gD | `From stdpp Require Import base sets listset.` + `Require Import Timbda.Syntax` (kernel package) | 5/5 closed - no clash: stdpp re-exports the *same* `Stdlib.Bool` notation, and `Timbda.Syntax` does not pull `CTree.Eq.WBisim` |
| gE | stdpp first, then `CTree`/`Eq`/`WBisim` + `Timbda.Syntax Rewriting Semantics Denotation` | **fails**: `Notation "_ &&& _" is already defined at level 40 … while it is now required to be at level 59` |
| gE2 | same stack, stdpp last | **fails**, mirrored error: `… already defined at level 59 … now required to be at level 40` |
| gE5 | `From Stdlib Require Import ZArith Bool List.` + `CTree`/`Eq`/`WBisim`, **no stdpp** | **fails** with the level-40 error - the collision is kernel-side and stdpp-independent |
| gE3 (control) | `CTree`/`Eq`/`WBisim` + the four kernel modules, no stdpp, no Bool import; `Print Assumptions` | compiles; `denote` closed, `Br2_Commut_W`/`Br2_Assoc_W` print exactly `Eqdep.Eq_rect_eq.eq_rect_eq` |
| gF (control) | `From Stdlib Require Import ZArith List.` + `CTree`/`Eq`/`WBisim` (no Bool) | clean |

### 7.2 Decision

**Candidate sets stay ctrees `br2` branchings read up to weak bisimilarity (`≈`)** -
`denote : Expr -> fuel -> ctree void1 B2 SResult`, `T1`/`T2`/`T8` stated at the `≈`
level (`docs/PLAN.md` § 3, § 5).  Consequences measured above:

- A `gset` carrier is *possible*: Leibniz-level AC reasoning works out of the box once the
  key type is `Countable` (gA1/gA2).  The cost is the instance work - hand-written
  `EqDecision` + `Countable` for the mutually-recursive `Val`/`Expr`/`SResult` domain (gB1) -
  and the `listset` shortcut around that domain only reaches `≡`, not `=` (gC2).
- `listset` would make candidate equality setoid-level (`≡`), which weakens `T8`'s
  statement (the trace-equality claim needs `≈` on ctrees anyway).
- The notation collision (7.3) makes any single file that wants *both* stdpp's set
  layer and ctrees' `WBisim` layer a build breaker, in either import order (gE/gE2), so a
  stdpp candidate-bag layer would have to live in its own compilation units behind a
  hand-managed import boundary.  That collision is not stdpp's fault: `Stdlib.Bool` +
  `CTree.Eq.WBisim` alone trips it (gE5), which is why `coq/Denotation.v` already avoids a
  direct Bool import.
- Therefore: `br2`/`≈` is the carrier for M0-M1.  stdpp stays pinned
  (`tools/pins/pins.toml [formal.stdpp]`, note added) for a possible M2/M3
  candidate-bag/ownership layer, and is deliberately **not** in `flake.nix`'s
  `rocqDeps` because nothing in `coq/` imports it.  Pinned ctrees sources contain no
  `&&&` and no stdpp reference (checked against
  `/nix/store/v24v7rhqmijml7hvqckq7yvq15qgnmxc-timbda-pin-sources`).

### 7.3 Notation-attribution probes (gG1-gG9, gH1-gH2)

`rocq compile` + `Locate "&&&"`, one layer per compilation unit.  (Every probe that loads
ctrees also prints the upstream `_ ° _` / `_ ~ 1` `notation-incompatible-prefix` warnings and
the `COQPATH` deprecation notice; both are noise from the pinned deps, not from Timbda.)

| Probe | Loaded | `Locate "&&&"` / error |
|---|---|---|
| gG1 | nothing | `Unknown notation` |
| gG2 | `From Stdlib Require Import Bool.` | `(from Stdlib.Bool.Bool)` – level 40, left assoc, `lazy_bool_scope` |
| gG8 | `From stdpp Require Import base sets listset.` | the **same** entry, `(from Stdlib.Bool.Bool)` – stdpp re-exports, does not define its own |
| gG7 | `From CTree Require Import CTree Eq.` | `Unknown notation` (core+Eq alone does not put level 59 in scope) |
| gG4 | `From CTree Require Import CTree Eq.` + `From CTree.Eq Require Import WBisim.` | `(from RelationAlgebra.common)` – level 59, right assoc |
| gG6 | `From RelationAlgebra Require Import common.` then `From Stdlib Require Import Bool.` | level 59 entry, then **`Error: Notation "_ &&& _" is already defined at level 59 … while it is now required to be at level 40`** - the minimal repro, no ctrees and no stdpp involved |
| gG5 | kernel chain (`CTree` + `Eq` + `WBisim`) then `From Stdlib Require Import ZArith Bool List.` | same clash, roles swapped |
| gH2 | `From Stdlib Require Import ZArith Bool List.` + `From CTree Require Import CTree Eq.` (no `WBisim`) | level 40 entry only - this is today's `Timbda.Semantics` configuration, clean |
| gG9 | `From stdpp Require Import base sets listset.` + `From CTree Require Import CTree Eq.` | compiles; level 40 entry only - stdpp coexists with ctrees core/Eq, not with `WBisim` |
| gH1 | `Timbda.Syntax Rewriting Semantics Denotation` in one unit | `Unknown notation` - notation tables of transitively-loaded modules are not replayed |

**Rule to keep the kernel buildable:** a compilation unit may directly import the ctrees
`Eq`/`WBisim` layer *or* `Stdlib.Bool`/stdpp, never both.  `coq/Denotation.v` takes the
ctrees side (no Bool import); `coq/Semantics.v`, `coq/Eval.v`, `coq/Syntax.v` take the
Bool side and never import `WBisim`; `coq/tests/KernelTest.v` omits Bool deliberately.
Bool reaches `Denotation.v` transitively through `Timbda.Syntax` (gH1 shows that does not
replay the level-40 table).

## 8. Extraction + the corpus corner (measured 2026-11-18)

The M0 tail is PLAN § 5's "extracted evaluator" plus the differential-corpus half of
PLAN § 6.  Layout and the claims it backs are in `tools/corpus/README.md`; the numbers
below are from the pinned toolchain (rocq-core 9.1.1, OCaml 4.14.4, pins `[toolchain.extraction]`).

### 8.1 Extraction on rocq 9.1 (measured)

- `Extraction` is a **plugin**: the bare keyword is a syntax error (`Error: Syntax error:
  illegal begin of vernac.`) until the theories file that carries
  `Declare ML Module "rocq-runtime.plugins.extraction"` is Required.  On 9.1 that file is
  `lib/coq/theories/extraction/Extraction.v` and its glob reads `FCorelib.extraction.Extraction`,
  so the import is `From Corelib.extraction Require Import Extraction.`.
- `Set Extraction Output Directory "."` + `Extraction "timbda_eval.ml" …` writes beside the
  compilation unit.  Without it rocq 9.1 warns and defaults to the compilation dir; in a nix
  build that *is* the build dir (nix mounts it at `/build`), which is why the first probe's
  output was found in `$PWD`.
- Extracted from `Timbda.Eval.norm`, `Timbda.Eval.head_redex`, `Timbda.Eval.selected_rows`:
  one self-contained 1094-line `.ml` (no external findlib dependency), `Print Assumptions
  Timbda.Eval.norm` prints **`Closed under the global context`**, and the extracted type
  shapes the driver must construct are: `nat = O | S`, `positive = XI | XO | XH`,
  `z = Z0 | Zpos | Zneg`, `'a list = Nil | Cons`, `'a option = Some | None`,
  `('a,'b) prod = Pair`, `iterComb = IAll | IIf | IFor`, `val0`/`expr` (with `Fail` as a
  nullary constructor of `expr`), `primResult = PRes | PFail | PStuck`, and `ruleID` with all
  27 row names (the head table only ever returns 16 of them - `Eval.v`'s `selected_rows`).
- `Extraction "timbda_eval.ml"` also emits `timbda_eval.mli`, so the build compiles the interface
  first (`ocamlc -c timbda_eval.mli`) and then `ocamlc -o corpus-run timbda_eval.ml driver.ml`.  That
  is not ceremony: the driver is then type-checked against the extracted signature, so a kernel change
  that changes the extracted shape breaks the build instead of silently changing what gets compared.
- `rocq compile` (no dune) resolves `Require Import Timbda.*` only if the kernel package's
  `lib/coq/9.1/user-contrib` is on `ROCQPATH`.  nixpkgs' setup hooks add the *library* packages, not
  our own kernel derivation, so both corner build phases export it explicitly.
- Harness wiring in `flake.nix`: packages `timbda-corpus-coq-corner` (corpus → generated
  `corner.v` → `rocq compile`) and `timbda-corpus-ocaml-corner` (extract → compile → run), plus
  the check `checks.corpus-differential`, which builds both corners, requires both to accept
  every case and the case counts each corner sees to be equal, and writes `$out/report.txt`.
  All of it lives in `tools/` + `tests/`, so `dune build` over `coq/` and the § 6 axiom gate
  are untouched by harness work.

### 8.3 Corners write a status file; the check reads it (design rule, measured)

The first version of these corners "passed" while running nothing.  Two causes, both worth
remembering: (i) the corpus and driver files were untracked, and a flake whose `src = ./.` sits in a
git repo exposes only tracked files, so the corner build dirs were missing their inputs; (ii) `rocq c`
on an *empty* `corner.v` exits 0, so "the Coq corner compiled" was vacuously true.  Each corner now
writes a `status.txt` and the check reads it:

```
coq corner:      reader_rc=0  reader_cases=49  corner_lines=315  rocq_rc=0  marker=corner_cases = 49
extracted corner: extract_rc=0  extracted_lines=1094  mli_rc=0  ocamlc_rc=0  driver_rc=0
                  corpus corner: 49 cases, all agree with the extracted evaluator
```

The check fails on any non-zero status, on `reader_cases = 0`, on a generated corner of `<= 100`
lines, on an extraction of `<= 200` lines, and on a case-count disagreement between the corners.
Rule to keep: **a differential corner must fail on vacuity, not only on mismatch** — the cheap failure
mode of a generated-test harness is generating nothing.

### 8.2 Corpus findings (49 cases; 37 fire a row, 12 assert `head none`)

- **`seq_z` was off by one (kernel fix).**  Fig. 10 line 459 (`dotdot[ki1, ki2] ⟶
  ki1 (ki1+1) … ki2`) is inclusive, and the pinned oracle agrees with it
  (`verse-semantics/reduction/Red.hs:1384`: `[Res (IntE i) | i <- [l..h]]`; its own tests,
  e.g. `for(x:=1..3){x}` → `(1,2,3)`).  `coq/Syntax.v` gated the range on `Z.ltb lo hi`, so
  `1..3` materialised as `⟨1,2⟩`: the corpus case `prim_dotdot_range` disagreed with what the
  kernel itself computed, and the guard is now `Z.leb lo hi` (whose fuel
  `|hi-lo|+1` is then exactly the inclusive length, and `lo > hi` gives `nil`, matching
  Haskell's `[l..h] = []`).  `KernelTest.v` pins the boundary cases (`dotdot_range_inclusive`,
  `dotdot_single_element`, `dotdot_descending_empty`) so it cannot drift back.
  Consequence for the proofs: none of them reduced `seq_z` concretely - `RewSound_DotDot`
  rewrites with `closeV_map_VInt` and keeps `map VInt (seq_z a b)` symbolic on both sides -
  so the definition change needed no proof edit; the kernel rebuild re-ran the § 6 gate.
- **Division rounding is now pinned, not assumed.**  Fig. 10 line 452 states `ki1 / ki2`
  without giving the rounding for negative operands.  The kernel uses `Z.div` (floors:
  `(-7)/2 = -4`), the oracle uses Haskell `div` (`Red.hs:1347`, also floors), and the corpus
  case `prim_div_negative_floor` records that agreement, and both corners confirm it independently
  (the Coq corner discharges `norm … = (Ret (VInt (-4)))`, the extracted corner computes the
  same `-4`), so a later change on either side shows up as a corner failure rather than as a drift
  in a comment.
- **`norm`'s two behaviours are separate claims.**  Head steps repeat (fuel decrements per
  step: `unify 3 (seq unit fail)` → Norm1 → `seq unit (unify 3 fail)` → `Seq`-of-a-value →
  `unify 3 fail`), while a stuck head rebuilds its children bottom-up with the same fuel and
  is **not** re-tried (`eqtup1_single_element`'s normal form is the half-rebuilt
  `seq (ret unit) (ret (tupv unit))` at any fuel).  Expectations that mixed these up were the
  two initial corner failures; both were resolved on the corpus side, not on the kernel side.
- Coverage note: 11 of the 27 `RuleID`s are never exercised (`R_Subst`, `R_Gc1`,
  `R_PromoteL/R`, `R_Iter*`, `R_HpAlpha`, `R_LamAlpha`) because `Eval.v`'s head table defers
  them (M2/M3 items) - `corpus.py --summary` prints that list rather than hiding it.
