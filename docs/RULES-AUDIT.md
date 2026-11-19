# Timbda-0 rule audit (RULES-AUDIT)

M0 seed of the per-rule audit rows required by `docs/VERSE-RULES.md` (header item 3:
"an entry in `docs/RULES-AUDIT.md` with tier and proof status").  At M1
(`docs/PLAN.md` § 5) `tools/rules-audit.py` becomes the generator: it diffs this file's
rows against the `audit:` tags of the `Rew` constructors in `coq/Rewriting.v`, the
`RuleID`/`selected_rows` tables in `coq/Eval.v`, and the `TimbdaRule` records in
`dialect/Timbda.td` — the diff IS the completeness claim (PLAN § 11.2).  Until that tool
exists this file is hand-maintained and is the source of record for proof status.

What "status" measures:

* **T1** — the per-rule soundness statement `RewSound_<Rule> : … ⟦lhs⟧ ≈ ⟦rhs⟧` (ctrees
  weak bisimilarity), discharged per constructor in `coq/Denotation.v`.
* **T2** — the branch algebra the choice handling relies on (`br2` laws + the bind/br2
  interchange), § 4.
* **Gate check.**  PLAN § 5 M0: "T1 for ~12 core rules, T2"; VERSE-RULES § 0 calibration:
  "M0 gate: ≥ 10 full proofs".  Both are met: **15 named constructors discharged** plus
  the two PrimSchema constructors discharged at both arities the kernel primop table
  uses, plus the `br2` algebra (minus the tracked bind/br2 corner, § 4).

`tier` reproduces the `tier:` tag in `coq/Rewriting.v` and classifies the *statement*:
tier 2 = the constructor's own statement needs the evolving-heap model (`hp[v/x]`,
C-general float).  It is **not** a proof tier: a tier-1 tag does not mean "discharged at
M0" (M0's gate is the ~12-rule scope above), and a tier-1 row may still be deferred.
The deferral *cause* is the reason class of § 3.

## 1. Kernel rows — the 35 `Rew` constructors

`sel` = whether `coq/Eval.v`'s head table selects the row (`R_Prim`/`R_PrimFail` stand in
for the named Fig. 10 rows; "M2"/"M3" = selection needs that milestone's machinery).  As of
the M0 close-out (2026-11-18) the Fig. 8 rows `Subst`, `PromoteL`, `PromoteR` are selected
at a `Block` root and `Gc1` is not; see § 1's `Count` note for what that does and does not
license.  `IsEss` = the VERSE-RULES § 0/§ 4 Essential-Verse flag: 0 for every kernel
row (Timbda-0 implements Core Verse only); the § 2 records carry it.

| ctor | rule | fig | tier | IsEss | sel | T1 status | proof / deferral reason (class of § 3) |
|---|---|---|---|---|---|---|---|
| `RewEqK1` | EqK1 | 9 | 1 | 0 | R_EqK1 | **discharged** | `RewSound_EqK1` (literal-general form: k ranges over unit/true/false/int, line 432) |
| `RewEqK2` | EqK2 | 9 | 1 | 0 | R_EqK2 | **discharged** | `RewSound_EqK2` (`Z.eqb_eq` decision on the int-literal pair) |
| `RewEqTup1` | EqTup1 | 9 | 1 | 0 | R_EqTup1 | deferred | **chain-induction (C2)**: RHS is the `eq_seq` `Seq`-chain; needs the `unify_seq`/`eq_seq` computation lemma + per-node fuel accounting |
| `RewEqTup2` | EqTup2 | 9 | 1 | 0 | R_EqTup2 | **discharged** | `RewSound_EqTup2` (`length_map` + `Nat.eqb_eq`) |
| `RewEqFail` | EqFail | 9 | 1 | 0 | R_EqFail | **discharged** | `RewSound_EqFail` (root taxonomy `root_mismatch`/`no_eq_rule_pair`; λ=λ and x=x stay SStuck, lines 441-445 — those *absent* rules are the design row of VERSE-RULES § 2) |
| `RewAdd` | Add | 10 | 1 | 0 | R_Prim | **discharged** | `RewSound_Add` (fuel `S^5 f`) |
| `RewGt1` | Gt1 | 10 | 1 | 0 | R_Prim | **discharged** | `RewSound_Gt1` (reflection lemma `prim_total_PGt_true`) |
| `RewGt2` | Gt2 | 10 | 1 | 0 | R_Prim | **discharged** | `RewSound_Gt2` (`prim_total_PGt_false`) |
| `RewIsInt1` | IsInt1 | 10 | 1 | 0 | R_Prim | **discharged** | `RewSound_IsInt1` (fuel `S^4 f`) |
| `RewIsInt2` | IsInt2 | 10 | 1 | 0 | R_Prim | **discharged** | `RewSound_IsInt2`; hypothesis on the **closed** instance (convention G1, § 5); the ctor keeps the paper's open form |
| `RewCons` | Cons | 10 | 1 | 0 | R_Prim | **discharged** | `RewSound_Cons` |
| `RewDotDot` | DotDot | 10 | 1 | 0 | R_Prim | **discharged** | `RewSound_DotDot` (kernel form: range as `VTup (map VInt (seq_z a b))`, rewritten with `closeV_map_VInt`) |
| `RewPrim` | PrimSchema (*SCHEMA record, not among the 33 named rows*) | 10 | 1 | 0 | R_Prim | **partial** | discharged at the arities the `prim_total` table uses (1 and 2): `RewSound_Prim1/Prim2`; variable-length form deferred (C2: `denE_tup` fuel needs `Nat.add (length vs) f`, stuck for a variable `length`) |
| `RewPrimFail` | PrimSchemaFail (SCHEMA record) | 10 | 1 | 0 | R_PrimFail | **partial** | same: `RewSound_PrimFail1/PrimFail2` discharged; n-ary deferred (C2) |
| `RewBetaL` | BetaL | 11 | 1 | 0 | R_BetaL | deferred | **evolving-heap (C1)**: RHS declares a `None` slot; under decision 3 that block is SStuck while the LHS (closure application) proceeds — the denotations genuinely differ until block-slot semantics exists |
| `RewBetaT` | BetaT | 11 | 1 | 0 | R_BetaT | deferred | C1; the candidate bodies close only via the promote rows |
| `RewBetaT0` | BetaT0 (kernel extension from line 475) | 11 | 1 | 0 | R_BetaT0 | **discharged** | `RewSound_BetaT0` (relies on the decision-5 fail short-circuit; fuel `S(S f)` covers the function arm only) |
| `RewSeq` | Seq | 12 | 1 | 0 | R_Seq | **discharged** | `RewSound_Seq` (fuel `S(S f) → S f`) |
| `RewNorm1` | Norm1 | 12 | 1 | 0 | R_Norm1 | deferred | **fuel rebudgeting (C3)**: node moved across the `=`/`;` boundary; needs the fuel-transfer/monotonicity lemma that M2's T8 adequacy proof also depends on |
| `RewNorm2` | Norm2 | 12 | 1 | 0 | R_Norm2 | deferred | C3 |
| `RewNorm3` | Norm3 | 12 | 1 | 0 | R_Norm3 | deferred | C3 |
| `RewNorm4` | Norm4 | 12 | 1 | 0 | R_Norm4 | deferred | C3 (progress role, paper lines 502-503) |
| `RewNorm5` | Norm5 | 12 | 1 | 0 | R_Norm5 | deferred | C3 (de-clutter, line 504) |
| `RewHpAlpha` | HpAlpha | 12 | 1 | 0 | never | **discharged** | `RewSound_HpAlpha` = `reflexivity`: under de Bruijn a renaming *is* the identity; the head table never fires it; the named-syntax rename is the M1 dialect pattern |
| `RewLamAlpha` | LamAlpha | 12 | 1 | 0 | never | **discharged** | `RewSound_LamAlpha`, same treatment |
| `RewFloat` | Float | 12 | **2** | 0 | no (M3) | deferred | C1 + the C-general form needs the flatten-substitution lemma; kernel states C = □ with a free `sx ++ sy` merge (outermost-first slots) |
| `RewSubst` | Subst | 8 | 1 | 0 | **yes** (`R_Subst`, M0 close-out) | deferred | C1: block-slot completion semantics (decision 3); the kernel restriction (binder-free `CtxS`) is recorded at the ctor. Selected now by the head table's `Block` arm (`body_walk`), which is a *strategy* fact, not a licence: `RewSound_Subst` is still what T1 owes, and its lhs (a `None` slot) is SStuck in the M0 denotation while its rhs is not |
| `RewGc1` | Gc1 (kernel split of the paper's Gc) | 8 | 1 | 0 | no (M2) | deferred | C1, plus the `dropSlot`/`shrinkE` reindexing computation lemma; the SCC (recursive-heap) form is the no-ctor record `Gc-Rec`, § 2. Stays unselected deliberately: without the reindexing lemma there is nothing to check the slot-shrinking against |
| `RewPromoteL` | PromoteL | 8 | **2** | 0 | **yes** (`R_PromoteL`, M0 close-out) | deferred | tier 2 by statement: `hp[v/x]` is restricted to the identity via `promote_hp_ok`; the general evolving-heap form is the M3/T1 obligation. Selected now (it is the row that closes a BetaL/BetaT `x = v`), so the C1 divergence is *reachable* from `head_redex`, not just latent |
| `RewPromoteR` | PromoteR | 8 | **2** | 0 | **yes** (`R_PromoteR`, M0 close-out) | deferred | as PromoteL; kept separate because the paper rules out a swap rule (lines 425-428: `x = y` could loop) — the kernel tries the two directions as two independent matches for the same reason (`promote_dir`) |
| `RewIterFail` | IterFail | 13 | 1 | 0 | no (M3) | deferred | **iter/choice corner (C4)**: context-hole matcher (CtxC walk) + an `iter_step`/`closeSlots` computation lemma |
| `RewIterChoice` | IterChoice | 13 | 1 | 0 | no (M3) | deferred | C4, and its ctrees-side content *is* the bind/br2 interchange — § 4 |
| `RewIterIf` | IterIf | 13 | 1 | 0 | no (M3) | deferred | C4 |
| `RewIterAll` | IterAll | 13 | 1 | 0 | no (M3) | deferred | C4 |
| `RewIterFor` | IterFor | 13 | 1 | 0 | no (M3) | deferred | C4; its RHS also declares a `None` slot (C1 boundary) |

**Count.**  15 discharged ctors + 2 partial schema ctors + 18 deferred ctors = 35.
VERSE-RULES § 7's "33 constructors" excludes the 2 SCHEMA records (its own § 3 note);
reconciliation in § 2 below.

**Selected vs discharged is not the same column, and the M0 close-out widened the gap.**
`coq/Eval.v`'s `selected_rows` now lists 19 `RuleID`s.  They stand in for 26 of the 35
ctor rows: 24 rewrite ctors (`Seq`, `Norm1-5`, `EqK1`, `EqK2`, `EqTup1`, `EqTup2`,
`EqFail`, `BetaL`, `BetaT`, `BetaT0`, `Subst`, `PromoteL`, `PromoteR` + the seven named
Fig. 10 ctors `Add`, `Gt1`, `Gt2`, `IsInt1`, `IsInt2`, `Cons`, `DotDot`, which fire through
the `R_Prim`/`R_PrimFail` arms) plus the 2 schema records themselves.  Nine ctors are
listed and never fired: `Gc1`, `Float`, the five `Iter*`, `HpAlpha`, `LamAlpha`.  Of the 24
fired rewrite ctors, 13 have a discharged `RewSound_*` (`Seq`, `EqK1`, `EqK2`, `EqTup2`,
`EqFail`, `BetaT0` and the seven named prim rows) and 11 do not (`Norm1-5`, `EqTup1`,
`BetaL`, `BetaT`, `Subst`, `PromoteL`, `PromoteR`).  Three of those eleven — Subst,
PromoteL, PromoteR — became *selectable* in this close-out while their soundness stayed
deferred (BetaL/BetaT were already in that situation).  The audit reads that as a debt made
visible, not as progress: a selected row without a soundness lemma is a strategy the
denotation does not yet license, which is why T8 (adequacy of `norm`) stays an M3
obligation and why the corpus records the binding cases as `SStuck`-vs-value divergences
instead of claiming agreement.

## 2. Kernel-adjacent and Essential records (no `Rew` ctor at M0)

| record | fig | tier | IsEss | status |
|---|---|---|---|---|
| `Gc-Rec` — GC's SCC form over mutually-recursive heaps | 8 | 2 | 0 | audit record, no ctor (VERSE-RULES § 3.2); M3/T1 obligation |
| `Subst-Deep` — rewriting *in place* inside slot values (the paper's `B[S ]`, `lambda x.B[S ]`) | 6/8 | 2 | 0 | audit record, no ctor (Rewriting.v context-closure note); deferred |
| `Match_*` — the 18 matching-function records | 14-15 | 2 | 1 | **deviation DEV-1**: VERSE-RULES § 4 says `match_pat` exists in `coq/Semantics.v` as the definitional basis — it does **not** exist at M0 (no `Match` node in `Syntax.v` either); pure record, M3 obligation |
| `Verify_MFun`, `Verify_MOFType`, `OFType` (+ `moftype` Core-Verse fragment) | 16 | 2-3 | 1 | audit records; rejected by the Core-Verse legality checker |
| `typeof` | — | 3 | 1 | audit record; VERSE-RULES § 4 calls it a kernel constructor with a Tier-3 admitted stub — **no such ctor or stub exists at M0** (deviation DEV-2); lands with M3's typeof rules |
| `Verify_*` — solver + v-* + split-* rows | 17 | 3 | 1 | 10 audit records (VERSE-RULES § 4.1); paper-side *incomplete* elsewhere is Fig. 18, not these |
| `Olam_Unify`, `Olam_App`, `Olam_ExiApp` | 18 | 3 | 1 | 3 audit records; the paper marks Fig. 18 incomplete |

Arithmetic for § 7's "68 records": 33 named ctor rows + 18 matching + 4 essential-verse
+ 10 verify + 3 open-lambda = 68.  This file additionally carries the 2 SCHEMA ctor rows
and the 2 kernel-adjacent records (`Gc-Rec`, `Subst-Deep`) → **72 rows** total; M1's
diff must expect 72, not 68.

## 3. Deferral reason classes

* **C1 — evolving-heap.**  Semantics.v decision 3: a block with a declared-unvalued
  (`None`) slot is SStuck in the denotation.  Rules whose RHS *creates* such slots or
  whose statement rewrites the heap (`hp[v/x]`) have LHS/RHS denotations that genuinely
  differ until block-slot semantics exists (the M2 Get/Put state-handler reading;
  promote completion).  Rows: BetaL, BetaT, Subst, Gc1, PromoteL, PromoteR, Float.  A
  soundness *statement* for these would be false today, so none is stated — and no
  `Admitted` placeholder either (§ 6).
  **M0 close-out makes C1 reachable, not latent:** the head table now *selects* BetaL,
  BetaT, Subst, PromoteL and PromoteR (`Gc1` and `Float` stay unselected), and the whole
  point of selecting them is the direction of the divergence — a `Block` with a `None`
  slot that decision 3 calls SStuck is rewritten into one whose slots are complete, so
  `norm` reaches a value where the old head table ended stuck (`KernelTest.v` section D:
  `(\x.x) 7` normalizes to `Block [(TAny, Some (VInt 7))] (Ret (VInt 7))`).  What is
  *not* claimed there: that the denotation agrees with the normal form.  An earlier draft
  of this close-out asserted `denote e 24 = denote (norm 24 e) 24` for that term; it was
  measured to be unprovable (`reflexivity`: `Unable to unify`; `vm_compute` at fuel 4:
  open goal) and machine-catastrophic (`vm_compute` at fuel 24 never finished), and the
  claim is gone from `KernelTest.v`, which now records the measurement instead.  Adequacy
  is an `≈` (Wbisim) statement with a fuel transfer — see § 3's C1 note and `KernelTest.v`'s
  comment at the `norm_beta_is_value` probes.  `head_redex` is *not* a proof of anything: T1 still owes these five
  `RewSound_*` lemmas, and until it pays them the adequacy claim (T8) for programs that
  bind is unproved, not contradicted.  What the corpus does is pin the observable shape of
  the divergence so the M2 evolving-heap semantics has something concrete to match.
* **C2 — schema/chain induction.**  EqTup1 (RHS = `Seq`-chain of length n) and the
  variable-length PrimSchema forms need induction over the argument list *together with*
  fuel accounting (`denE_tup` budget `Nat.add (length vs) f`, not a constant).  Nothing
  semantic is missing; the computation lemma is.  Note the shape/fuel split: what makes
  `closeSlots` consume `length sl` fuel is the *fold shape* of `closeSlots_aux`
  (one unit per slot), not the value `f` stands for — so a discharged row's fuel transfer
  is a bookkeeping fact about the interpreter, and re-running it at a different `f` is a
  different lemma, not the same one funded differently.
* **C3 — fuel rebudgeting.**  Norm1-Norm5 relocate evaluation nodes across `=`/`;`;
  each side consumes a different node count under uniform fuel.  Discharging them needs
  a `denE` fuel-monotonicity lemma — the same lemma M2's T8 adequacy draft leans on.
  Same caveat as C2: the rebudgeting is a consequence of the fold shape (`denE_seq`/
  `denE_unify` charge per node), so "fuel" here is interpreter bookkeeping; it is not a
  claim about how much evaluation the program does, and it is not fundable by choosing a
  bigger `f`.
* **C4 — iter/choice corner.**  IterFail/IterChoice/IterIf/IterAll/IterFor: the CtxC
  context-hole matcher and an `iter_step`/`closeSlots` computation lemma; IterChoice
  additionally needs the bind/br2 interchange at `≈` (§ 4).

## 4. T2 — branch algebra status

* **Discharged:** `Denote_Choice` (⟦b1 b2⟧ = `br2`), `Br2_Commut_W`, `Br2_Idem_W`,
  `Br2_Assoc_W`, `Br2_StuckL_W` — all transported from ctrees' sbisim laws through
  `sbisim_wbisim_subrelation` (the two relations are different fixed points; applying a
  `~` lemma to an `≈` goal fails without the bridge).  M0 gate satisfied.
* **Tracked corner — bind/br2 interchange** (`x <- br2 p q;; k x ≈ br2 (x <- p;; k x)
  (x <- q;; k x)`, cited by VERSE-RULES § 6 as the M-algebra the first rules use):
  **stated nowhere, proved nowhere yet.**  Normalized at `≅` the two sides are
  `br branch2 (fun b => bind (if b then p else q) k)` and
  `br branch2 (fun b => if b then bind p k else bind q k)` — the lambda bodies are
  extensionally, not syntactically, equal.  **Deviation:** VERSE-RULES § 3.4 claims
  this law is "proved in ctrees"; the vendored ctrees has the sbisim `br2` algebra and
  the up-to-bind machinery (`bind_chain_gen`, WBisim.v:574) but *no* bind/br2
  distributivity lemma (grep over `theories/` is empty).  The up-to-bind coinduction is
  the known route; the corner is tracked, not believed impossible.

## 5. Statement conventions (discharged rows)

1. **Fuel transfer.**  Uniform-fuel denotation (decision 2): each lemma fixes a
   residual `f`; LHS/RHS fuel is chosen so every sub-evaluation *below* the rewritten
   node sits at the same fuel on both sides.  Unify/Seq/BetaT0 rows: `S(S f)` LHS with
   `S(S f)` or `S f` RHS; prim rows: `S^4 f` (1 arg), `S^5 f` (2 args — head
   `Ret (VPrim p)` arm + `TupE` list arm + one unit per element); Choice: `S f → f`.
   A short budget appears as an unreduced `(fix denE …)` in the goal, never as an
   error.  Canonical counting: `coq/Denotation.v` header.
2. **G1 (closed-value hypotheses).**  The paper's meta-variables range over heap normal
   forms; the denotation closes values against the environment (`closeV`).  Hypotheses
   of IsInt2/Prim/PrimFail are stated on the closed instance
   (`prim_total p [closeV 0 rho v1; …] = …`); ctors keep the paper's open form.
3. **Two normalization vocabularies.**  `t1_norm` unfolds `prim_total` (rows whose RHS
   is a computed value); `t1_fold` keeps `prim_total p […]` folded (rows whose
   hypothesis is an equation about it: Gt1/Gt2/IsInt2/Prim/PrimFail rewrite against
   that form).  The `cbn` delta list must include `negb andb rev app length` (fixpoints
   only reduce when listed) and must exclude `Z.eqb`/`Z.ltb` (unfolding them destroys
   the occurrences the hypotheses rewrite against).  Hypothesis-driven boolean steps go
   through reflection lemmas (`zeqb_self_true`, `prim_total_PGt_true/_false`,
   `prim_total_PIsInt_fail`, `closeV_lit`, `closeV_map_VInt`), never goal-side
   `inversion`.
4. **PrimSchema arity convention.**  Discharged at 1 and 2 — the arities the kernel
   `prim_total` table and the head table actually use — with the n-ary generalization
   deferred (C2).  Named Fig. 10 rows are exactly the arities 1-2 instances.

## 6. `Admitted` / axiom audit (build-time evidence)

* **Zero `Admitted`** in every `coq/**/*.v` (grep-verified; deferred rows carry no
  statement rather than an admitted one).  **Zero axioms of our own** — no `Axiom`,
  `Parameter`, `Hypothesis` declarations in the Coq sources.
* `Print Assumptions` at build time (end of `coq/tests/KernelTest.v`; a
  `Denotation.v` tail too): every discharged `≈`-level lemma — and ctrees' *own*
  lemmas, e.g. `Probe.v`'s `ex_br2_commut` — prints exactly one axiom:
  `Eqdep.Eq_rect_eq.eq_rect_eq : forall (U : Type) (p : U) (Q : U -> Type) (x : Q p)
  (h : p = p), x = eq_rect p Q x p h`.
  It is inherited from ctrees' `Program`-generated definitions
  (`deps/ctrees/theories/Eq`), not introduced by Timbda.  Value-layer helpers
  (`closeV_lit`, `closeV_map_VInt`) print "Closed under the global context".
* Consequence for the claim boundary: "no axioms anywhere" is **not** the honest
  formulation; "no admitted proofs, no Timbda-introduced axioms, and a single named
  dependency on `eq_rect_eq` via the pinned ctrees layer" is.  Removing it would mean
  patching vendored ctrees (an upstream obligation, not an M0 one).
* VERSE-RULES § 0's Tier-2 calibration anticipates admitted `RewSound_*` statements;
  M0 practice (this file) records *deferrals with reason classes* instead.  The
  calibration's "M0 gate: ≥ 10 full proofs" is met with 15 discharged ctors + 2
  partials + the T2 algebra.
* Extracted-corner evidence (`tools/extract/extract.v`, compiled by the corpus corner): `Print
  Assumptions` on `Timbda.Eval.norm`, `Timbda.Eval.head_redex`, `Timbda.Eval.selected_rows` and
  `Timbda.Eval.cand_bag` prints **`Closed under the global context`** for all four.  The Gallina
  evaluator the C++ side will eventually inherit carries no axiom at all — unlike the `≈`-level
  lemmas above, whose `eq_rect_eq` footprint comes from the ctrees layer.
* One corpus case has already changed a kernel *definition*: `RewDotDot`'s range materialisation
  (`Syntax.v`'s `seq_z`) was guarded `Z.ltb lo hi` and is now `Z.leb lo hi` — paper line 459 is
  inclusive on both ends and the pinned oracle agrees (`verse-semantics/reduction/Red.hs:1384`,
  `i <- [l..h]`).  `KernelTest.v`'s `dotdot_range_inclusive` / `dotdot_single_element` /
  `dotdot_descending_empty` pin the boundary, and the 64-case corpus (`tests/corpus/m0.texpr`,
  gated by `checks.corpus-differential`) is what caught it.  No discharged proof needed editing:
  `RewSound_DotDot` rewrites with `closeV_map_VInt` and keeps `map VInt (seq_z a b)` symbolic on
  both sides.

## 7. M1 reconciliation checklist (`tools/rules-audit.py`)

1. `audit:` tag ↔ ctor ↔ § 1 row: 35/35 match, tier equal.
2. § 2 records ↔ `TimbdaRule`/`TimbdaExtern` records in `dialect/Timbda.td` (72-row
   arithmetic, § 2 note).
3. `sel` column ↔ `coq/Eval.v` `selected_rows`/`RuleID` (19 selectable rows of 27 `RuleID` ctors at
   M0; `corpus.py --summary` prints which fired and names the 8 never exercised).
4. Status column ↔ `RewSound_*` lemma existence + the `Print Assumptions` one-axiom
   pattern (§ 6).
5. Strategy-group column (Fig. 25 vocabulary, VERSE-RULES § 5) is the one § 1 column
   the dialect must add at M1; it is not carried per row here yet.
