# Timbda-0 Verse Rules — Tier-1 transcription

**Source of record:** "The Verse Language: its type system and semantics" (Supporting
Figures), Sweeney, Vitek, Sonnenberg, Peyton Jones, Augustsson, Claessen, Weirich —
SPJ School, June 2026. Figures 6–16, lines 319–613 (pp. 7–13). Everything below is a
verbatim transcription of the paper's rules, restated for **Timbda-0 (Core Verse)** with
our kernel naming. This file is the feed for three artifacts that must stay 1:1 with it
(`docs/PLAN.md` § 11.2 audit):

1. a `TimbdaRule` TableGen record in `dialect/Timbda.td` (+ `dialect/patterns/*.tdrr`),
2. a `Rew` constructor in `coq/Rewriting.v`,
3. an entry in `docs/RULES-AUDIT.md` with tier and proof status.

> Timbda-0 scope note: the paper's Figure 6 syntax is *Core Verse* extended with the
> Essential-Verse nodes `x ⇝w t` (matching), `verify(R;A){b}`, `e1 ▷⟨ω⟩ e2`. Timbda-0
> implements Core Verse only (PLAN § 4.1): literals (`Int`, `Bool`, `Unit`), tuples,
> first-class functions, `def`/`where`/ifs/loops, candidate sets (`b1 b2`, `select`),
> `fail`, `return`, `get`/`put` (Verse refs), `match`, `typeof`. The Essential-only nodes
> (`verify`, `▷`, typed matching `⇝w`) are **Tier-2 records**: they exist in the audit
> table and in the .td corpus as `TimbdaRule` records with `IsEssential = 1` (rejected by
> the Core-Verse legality checker), so the audit is complete against the paper, but they
> have no kernel constructor and no DRR pattern until M3+.

## Formalization calibration (PLAN § 4.4)

- **Tier 1** — proved in this repo or in the pinned ctrees stdlib, audit row links the
  Gallina lemma. Every rule below that has `Tier 1` gets a kernel constructor with a
  discharged `RewSound_*` lemma (M0 gate: ≥ 10 full proofs).
- **Tier 2** — Gallina statement + proof sketch (forward-simulation lemma stated,
  per-rule `RewSound_*` admitted where the full proof needs the evolving-heap model;
  M3/T1 completes them).
- **Tier 3** — `Admitted` with an audit row, non-blocking (M2 hard-gate).

Notation key: `∃X{hp}. e` = block `block{def(x1 t1){…}}` (binder set X, heap hp);
`hp[x v]` extends heap; `S[ ]` substitution context (Fig. 6 line 352); `C[ ]` evaluation
context (line 351); `fvs`, `bvs`, `fvsol`, `rng`, `dom` as in Fig. 7 / line 374–378;
`k`, `ki` integers literals; `hnf` head-normal forms; `;` sequencing; `=` unification;
`b1 b2` (juxtaposition of blocks) = internal choice = our `select`; `iter(ic){b}{e}`
with `ic ∈ {all, if, for}`.

## 0. Syntax (Fig. 6, lines 319–357)

Timbda kernel AST (`coq/Syntax.v`), locals as de Bruijn indices (autosubst idiom),
globals (`verse`/`host` names) as `ident`:

```
Ty    ::= Unit | Bool | Int | Arr ty ty                 (Core Verse table, PLAN § 4.1)
Expr  ::= Ret valF                                     (v, k, unit, true/false, op head)
       |  Var n | Glob ident                            (locals / verse-host globals)
       |  Lam ty e                                      (λx:T. e  — Core Verse lambdas are typed, lecture 3)
       |  App e e                                       (e1 [e2])
       |  Tup (list e)                                  (⟨v1, …, vn⟩; 0-ary = unit fail case in beta-t)
       |  Seq e e                                       (e1 ; e2)
       |  Unify e e                                     (e1 = e2)
       |  Choice e e                                    (b1 b2 — internal candidate choice)
       |  Fail                                           (fail)
       |  Delay e                                        (delay{e})
       |  Block b                                        (block{b})
       |  Def (list (pat × expr)) e                     (∃X{hp}. e as def(x1 := t1){e}; M0: non-recursive, see § 3.2)
       |  Iter itercomb e e                              (iter(ic){b}{e}; ic ∈ {all, if, for})
       |  Get e | Put e e | Select e e | Match e pat    (canonicalizer/Timbda ops: PLAN § 4.1 — no M0 rewrite rule touches Get/Put)
Pat   ::= Wild | Lit k | VarP n | DefP e | AnnP ty | TupP (list pat) | ApP pat pat | MatchP pat pat
       |  ChoiceP pat pat | SemiP pat pat | WhereP pat pat | ColonP pat pat? ... (Fig. 14/15 patterns, M3)
```

Kernel encoding **as implemented** in `coq/Syntax.v` (the mapping the M1 audit diff uses;
`docs/DESIGN-NOTES.md` § 1 has the index conventions):

| § 0 name | Implemented constructor | Note |
|---|---|---|
| `Var n` | `VVar : nat -> Val` in the *value* layer | locals are only meaningful as values (`v ::= x`, Fig. 6 line 325); `Expr` has no bare `Var` constructor, so every occurrence is `Ret (VVar n)` |
| `Lam ty e` | `VLam : Ty -> Expr -> Val` | Core-Verse lambdas are values (line 326 `λx.b`) |
| `Delay e` | `VDelay : Expr -> Val` | `delay{e}` is a value; it is also how the kernel stores a *not-yet-evaluated* heap binding (see below) |
| `Tup (list e)` | `VTup : list Val -> Val` *and* `TupE : list Expr -> Expr` | the paper's `op[a1, a2]` argument lists (line 452) and the Fig. 13 `cons [...]` right-hand sides hold **open expressions**, so the kernel needs an expression-level tuple; when all entries are `Ret`, `TupE` *is* the value tuple |
| `Def (list (pat × expr)) e` | `Block : list (Ty * option Val) -> Expr -> Expr` | one constructor for `block{∃X{hp}. e}`: the slot list is `X` (with `hp` entries as `Some v`); a `def(x := e)` binding whose `e` is not yet a value is written `Some (VDelay e)` — the paper's `x = e` heap-binding form, which the `Subst`/promote rules turn into a value binding, is kept *literally* as a `None` slot plus `x = e` in the body (rules `beta-l`/`beta-t`/`subst`) |
| `Get`/`Put`/`Select`/`Match` | no constructor in M0 | `Select` is `Choice`; `Get`/`Put` event carriers exist in `coq/Semantics.v` but are unused until M4/T12; `Match` is Tier-2 (Figs. 14–15) |
| `Pat` | no kernel type in M0 | pattern rows are the Fig. 14/15 audit records (M3) |

Kernel deviation from the paper, recorded in the audit: the paper's heap entries bind
*values* (`hp ::= x1 v1 … xn vn`, line 336); the kernel's `Def` binds *expressions*
(`x := e`) — Core-Verse `def` syntax only distinguishes them at normalization, and the
heap-binding form is recovered by the `Subst`/`Promote` rules. Non-recursive `def` in M0;
the fully-recursive heap (and the SCC side condition of GC) is an M3/T1 obligation
(Tier 2 row `Gc-Rec`).

## 1. Auxiliary functions (Fig. 7, lines 380–399) — Tier 1

Kernel: `coq/Syntax.v` defines `leftChoiceFree`, `choiceFree` structurally, exactly:

```
leftChoiceFree(□)          = True        leftChoiceFree(C = e)  = lcf(C)
leftChoiceFree(C ; e)      = True        leftChoiceFree(e = C)  = choiceFree(e) ∧ lcf(C)
leftChoiceFree(e = C)      = …           leftChoiceFree(e ; C)  = choiceFree(e) ∧ lcf(C)
leftChoiceFree(e [C ])     = False       leftChoiceFree(C [e])  = True   (kernel ext, see audit)
choiceFree(v)              = True        choiceFree(e1 ; e2)    = cf(e1) ∧ cf(e2)
choiceFree(e1 = e2)        = cf ∧ cf     choiceFree(e1 [e2])    = cf ∧ cf
choiceFree(fail)           = True        choiceFree(b1 b2)      = False
choiceFree(block{b})       = cf(e)       choiceFree(iter(all){b}{e}) = True
choiceFree(iter(if){b}{e}) = False       choiceFree(iter(for){b}{e}) = cf(e)
```

## 2. Unification (Fig. 9, lines 432–437)

| Rule | Paper form | Kernel constructor (`Rew`) | Tier |
|---|---|---|---|
| EqK1 | `k = k ⟶ k` | `RewEqK1 : Rew (Unify (Ret k) (Ret k)) (Ret k)` | 1 |
| EqK2 | `k1 = k2 ⟶ fail  if k1 ≠ k2` | `RewEqK2 : k1 ≠ k2 → Rew (Unify (Ret k1) (Ret k2)) Fail` | 1 |
| EqTup1 | `⟨v1..vn⟩ = ⟨w1..wn⟩ ⟶ v1=w1; … vn=wn; ⟨v1..vn⟩` | `RewEqTup1 : Rew (Unify (Tup vs) (Tup ws)) (Tup vs ⋯ sequencing)` — kernel form: `Seq (Unify v1 w1) (Seq … (Tup vs))` | 1 |
| EqTup2 | `⟨v1..vn⟩ = ⟨w1..wm⟩ ⟶ fail  if n ≠ m` | `RewEqTup2 : n ≠ m → … → Fail` | 1 |
| EqFail | `hnf1 = hnf2 ⟶ fail  if different root shapes` | `RewEqFail : root_mismatch h1 h2 → Rew (Unify (Ret h1) (Ret h2)) Fail` | 1 |
| — | no rule for `λx.e1 = λy.e2` (line 441); `x = x` stuck until `x` gets a value (line 444) | **no constructor**; the *semantics* returns `RStuck` for function-vs-function equality. Kernel `root_shape` has no `Lam`/`Var` case: `Unify` of non-literal roots is a **stuck** normal form (a term with no `Rew` redex). | 1 (design) |

Paper notes transcribed: there is deliberately no `x = x` rewrite (it must stay stuck in
case `x` is bound to a lambda — unification-by-rewriting must not guess); stuck = "goes
wrong at runtime", the verifier rejects such programs statically (M4 checker obligation,
Tier 3 for M0-M2: the kernel distinguishes `RStuck` from `RFail` in `SResult`).

## 2.1. Kernel-side note — `=` on open terms

In the kernel, `Unify e1 e2` with a *non-value* side has no rewrite rule from Fig. 9.
The Fig. 12 rules `Norm1–Norm4` move evaluation through `=`; the promotion rules (§ 3.3)
bind open variables when a value side meets them. What remains (two open sides, or a
function value against anything non-root-compatible) is a normal form whose semantics is
`RStuck` (Fig. 9, line 442).

## 3. Primitive operations (Fig. 10, lines 452–459)

Kernel: primop application is `App (Ret (PAdd …)) (Tup [e1; e2])`-style canonical
application: `op[v1, v2]` = `App (Prim op) (Tup args)`. The kernel enumerates the paper's
examples (line 449: "a small representative selection"); the *complete* primop table is
fed from the pinned `verse-semantics/Core/Expr.hs` `PrimOp` enum
(`Add Sub Mul Div Neg Pls ArrLen DotDot ArrApp ArrMap ArrCons Gt Lt NEq GEq LEq …`), and
the audit records which paper rules have a named constructor vs. which are covered by
the generic `RewPrim` schema. Ill-typed application is **stuck**, not `fail` (line 463:
`add[3, λx.x]` is just stuck — `RStuck` semantics, no rewrite).

| Rule | Paper form | Kernel constructor | Tier |
|---|---|---|---|
| Add | `add[ki1, ki2] ⟶ ki1 + ki2` | `RewAdd : Rew (App (PAdd) (Tup [Ret ki1; Ret ki2])) (Ret (ki1+ki2))` | 1 |
| Gt1 | `gt[ki1, ki2] ⟶ ki1  if ki1 > ki2` | `RewGt1` | 1 |
| Gt2 | `gt[ki1, ki2] ⟶ fail  if ki1 ≤ ki2` | `RewGt2` | 1 |
| IsInt1 | `isInt[ki] ⟶ ki` | `RewIsInt1` | 1 |
| IsInt2 | `isInt[v] ⟶ fail  if v not an integer` | `RewIsInt2` | 1 |
| Cons | `cons[v0, ⟨v1..vn⟩] ⟶ ⟨v0, v1, …, vn⟩` | `RewCons` | 1 |
| DotDot | `dotdot[ki1, ki2] ⟶ ki1 (ki1+1) … ki2` | `RewDotDot` (range literal `Range ki1 ki2` as value, per paper line 459) | 1 |
| Prim-schema | `op[gv…] ⟶ result-of-host-eval` or stuck | `RewPrim : prim_total op gvs = Some v → Rew (App (Prim op) (Tup gvs)) (Ret v)` — total-part function mirrors `Expr.hs primOpCanFail/PreCond` | 1 (schema), table Tier 1 |

`Mul Div Neg Pls Lt GEq LEq NEq ArrLen ArrApp ArrMap ArrMap…` audit note: no paper
figure rule; kernel `prim_total` defines them (Int arithmetic where defined; `Div 0` and
`ArrApp` out-of-bounds = partial → **stuck** per Fig. 10 note line 463; the host
primops from `Expr.hs` (`ChkFails ChkSucceeds ChkDecides …`) are Essential-Verse —
Tier 2 records, no M0 constructor).

## 3.1. Beta reduction (Fig. 11, lines 468–469)

| Rule | Paper form | Kernel constructor | Tier |
|---|---|---|---|
| BetaL | `(λx.b)[e] ⟶ block{∃x{}. x = e; block{b}}  if x ∉ fvs(e)` | `RewBetaL : Rew (App (Lam ty b) e) (Block1 b e)` — `Block1 b e` = `Def [(VarP 0, e)] b`-style: heap entry binds `e`; side condition automatic under de Bruijn (paper renames to satisfy `x ∉ fvs(e)`, line 404–405) | 1 |
| BetaT | `⟨v0,…,vn⟩[e] ⟶ block{∃x{}. x = e; ((∃{}. x = 0; v0) … (∃{}. x = n; vn))}` | `RewBetaT : Rew (App (Tup vs) e) (Def1 …narrowing…)  if n > 0` — narrowing semantics: tuple applied to an argument narrows the argument to length-`n` tuples (paper line 473 "beta-t does narrowing"; empty tuple base case yields failure, line 475 → `RewBetaT0`) | 1 |
| BetaT0 | base case `⟨⟩[e] ⟶ fail` (line 475) | `RewBetaT0` | 1 |

Paper notes: `x = e` binding in beta-t exists to avoid duplicating `e` (line 474) — the
kernel form mirrors this: the argument is bound once in the block heap. BetaL's heap
entry is a *value-binding* of a possibly-open `e`: in kernel blocks, `Def [(e, b)]` —
evaluation order: `e` is evaluated once when the binding is forced (see § 6 semantics,
`Def` clause), matching the paper's lazy-heap reading (rule `subst`, Fig. 8, fires only
when the heap entry is a value `x v`).

## 3.2. Substitution and promotion (Fig. 8, lines 412–417)

These are the *canonicalizer-adjacent* rules (they motivate the DRR canonicalization
passes of PLAN § 5.2):

| Rule | Paper form | Kernel constructor | Tier |
|---|---|---|---|
| Subst | `∃X{hp, x v}. S[x] ⟶ ∃X{hp, x v}. S[v]  if x ∉ bvs(S)` | `RewSubst : x bound-by-heap-value v in scope → Rew (DefB (hp ++ [(x,v)]) (S x)) (DefB (hp ++ [(x,v)]) (S v))` — de Bruijn: `x` = the index of a heap slot whose entry is a *value*; `x ∉ bvs(S)` = no binder of S shadows that index (decidable, kernel `not_shadowed`) | 1 |
| Gc | `∃X,Y{hp}. e ⟶ ∃X{hp_Y}. e  if Y # fvs(rng(hpY), e), Y ≠ {}` | `RewGc : unused-SCC Y of mutually-recursive heap bindings → drop them` — **M0 kernel restricts to non-recursive `def`**: constructor `RewGc1` (drop a heap entry whose variable is not free in the body *and* whose expression is effect-free… paper GC does not require effect-freedom for values — `x v` slots are already values; kernel's non-recursive restriction records the SCC side condition in a Tier-2 row `Gc-Rec`, admitted, M3/T1) | 1 (`RewGc1`), 2 (`Gc-Rec` admitted) |
| PromoteL | `∃X,x{hp}. C[x = v] ⟶ ∃X,x{hp[v/x], x v}. C[v]  if x ∉ dom(hp), fvsol(v) # dom(hp) ∪ {x}` | `RewPromoteL` — kernel: `Def (hp) (C (Unify (Var x) v)) ⟶ Def (hp ++ [(x, v)]) (C (Unify v v))`-style; requires the *evolving-heap* semantics to state soundness (`hp[v/x]` rewrites existing slots) — **Tier 2**: constructor + soundness statement, proof admitted for M0, discharged in M3/T1 | 2 |
| PromoteR | `∃X,x{hp}. C[v = x] ⟶ …just like promote-l` (line 417) | `RewPromoteR` | 2 |

Paper note (line 425–428): promote-r cannot be replaced by a `x = hnf ⟶ hnf = x` swap
because `x = y` (two locally-bound vars, one outer) could loop; recorded so the audit
knows *why* the dialect carries both patterns.

## 3.3. Structural and normalisation rules (Fig. 12, lines 479–491)

| Rule | Paper form | Kernel constructor | Tier |
|---|---|---|---|
| HpAlpha | `∃X,x{hp}. e ↔ ∃X,y{hp[y/x]}. e[y/x]  if y ∉ fvs(hp,e)` | **representationally trivial** under de Bruijn (renaming = identity on the kernel AST); constructor `RewHpAlpha` exists for audit completeness, soundness = `reflexivity`. The *dialect* (named syntax) carries the real rename pattern. | 1 |
| LamAlpha | `λx.e ↔ λy.e[x/y]  if y ∉ fvs(e)` | `RewLamAlpha`, same treatment as HpAlpha | 1 |
| Seq | `v ; e ⟶ e` | `RewSeq : Rew (Seq (Ret v) e) e` | 1 |
| Norm1 | `v = (e1 ; e2) ⟶ e1 ; v = e2` | `RewNorm1` | 1 |
| Norm2 | `v = (e1 = e2) ⟶ v = e1 ; v = e2` | `RewNorm2` | 1 |
| Norm3 | `(e1 ; e2) = e3 ⟶ e1 ; e2 = e3` | `RewNorm3` | 1 |
| Norm4 | `(v = e1) = e2 ⟶ v = e1 ; v = e2` | `RewNorm4` | 1 |
| Norm5 | `(e1 ; e2) ; e3 ⟶ e1 ; (e2 ; e3)` | `RewNorm5` | 1 |
| Float | `∃X{hx}. C[block{∃Y{hy}. e}] ⟶ ∃X,Y{hx,hy}. C[e]  if X # Y, Y ∉ fvs(C), fvsol(rng(hy)) # X` | `RewFloat` — scope extrication; kernel form on nested `Def`s; soundness needs the flatten-substitution lemma: **Tier 2** sketch (constructor + statement, admitted M0, discharged M3/T1). | 2 |

Paper notes (lines 502–504): Norm4 exists to make progress on `(x = p + 1) = 5` (unify
`x` with 5 may unlock `p`); Norm5 is "not strictly necessary… de-clutter". Both notes
recorded — the audit's exhaustiveness claim is *against the paper's list*, not against
our judgment.

## 3.4. Iteration and choice (Fig. 13, lines 515–523)

`iter(ic){b}{e}` with `ic ∈ {all, if, for}`; `B[ ]` block contexts `∃X{hp}.□`.

| Rule | Paper form | Kernel constructor | Tier |
|---|---|---|---|
| IterFail | `iter(ic){B[C[fail]]}{e} ⟶ e` | `RewIterFail : Rew (Iter ic (fillB (fillC Fail)) e) e` | 1 |
| IterChoice | `iter(ic){B[C[b1 b2]]}{e} ⟶ iter(ic){B[C[block{b1}]]}{iter(ic){B[C[block{b2}]]}{e}}  if leftChoiceFree(C)` — the paper's *candidate-splitting* rule; kernel `Choice` = `Select` op; side condition `leftChoiceFree(C)` is the kernel function of § 1 | `RewIterChoice` | 1 (T2 algebra: = `bind/br2` interchange, proved in ctrees) |
| IterIf | `iter(if){B[delay{e1}]}{e2} ⟶ block{B[e1]}` | `RewIterIf` | 1 |
| IterAll | `iter(all){B[v]}{e} ⟶ cons[B[v], e]` | `RewIterAll` | 1 |
| IterFor | `iter(for){B[v]}{e} ⟶ block{∃x{}. cons2[⟨x, B[v]⟩, e]}` | `RewIterFor` (`cons2` = kernel pair-cons primop) | 1 |

Paper note (line 416, 491): the freshness side conditions (`X # Y`, `fvsol …`) are
handled by alpha rules "silently" (line 404) — de Bruijn representation makes them
mechanical; the dialect's named-scoping patterns carry them as `TimbdaRule` side
conditions (mirrored from the kernel functions).

## 4. Matching (Figs. 14–15, lines 533–580) — Tier-2 records, M3 kernel obligations

These rules define the *matching function* `u ⇝w t` (the semantics of Essential-Verse
patterns; `w = (bb, dr, vx)` the four-way mode, `𝒟w⟦t⟧` the desugaring). For Timbda-0
they fix the semantics of the canonicalizer `match` op and are the M3 obligation
"the 14 matching rules become lowering patterns, each proven correct wrt the ctrees
candidate-set model" (PLAN § 5.2 M3). They are **not** `Rew` constructors in M0 — they
are Gallina *functions* in `coq/Semantics.v` (`match_pat`) whose equations audit as rows
(`Match_*`), proven in M3 (Tier 2; kernel function exists in M0 as the definitional
basis, unproven):

| Rule (Fig. 14) | Gloss |
|---|---|
| `mwild` | `u ⇝w − → u` |
| `mlit` | `u ⇝w k → u = k` |
| `mvar` | `u ⇝w y → u = y` |
| `mdef` | `u ⇝w x := t → x = (u ⇝w t)` |
| `minp` | `u ⇝w x : t → x = u; u ⇝w t` |
| `mblock` | `u ⇝w block{t} → block{∃tbs(t){}. u ⇝w t}` |
| `mapp` | `u ⇝w t1[t2] → u = 𝒟w⟦t1⟧[𝒟w⟦t2⟧]` |
| `munif` | `u ⇝w t1 = t2 → (u ⇝w t1) = (u ⇝w t2)` |
| `mchoice` | `u ⇝w t1 t2 → (u ⇝w block{t1}) (u ⇝w block{t2})` (choice = candidate split) |
| `mfail` | `u ⇝w fail → fail` |
| `msemi` | `u ⇝w t1 ; t2 → 𝒟w⟦t1⟧ ; u ⇝w t2` |
| `mwhere` | `u ⇝w t1 where t2 → ∃y{}. y = (u ⇝w t1); 𝒟w⟦t2⟧; y` — "careful to keep t1 and t2 in the same order, in case they have effects" (line 566) |
| `mtup` | `u ⇝w array{t1 …tn} → block{∃u1…un, y1…yn{}. u = ⟨u1…un⟩; y1=(u1⇝w t1); …; ⟨y1…yn⟩}` |
| `mcolon1` | `x ⇝w :t → 𝒟w⟦t⟧[x]` |
| `mif` | `u ⇝w if(t0){t1} else {t2} → iter(if){∃tbs(t0){}. 𝒟w⟦t0⟧; delay{u⇝w block{t1}}}{u⇝w block{t2}}` |
| `mall` | `u ⇝w for{t} → u = iter(all){∃tbs(t){}. 𝒟w⟦t⟧}{⟨⟩}` |
| `mfor` | `u ⇝w for(t0) do{t1} → block{∃y{}. ⟨u,y⟩ = iter(for){…𝒟w⟦t0⟧; λu'. u'⇝w block{t1}}{⟨⟨⟩,⟨⟩⟩}; y}` |
| `mfun` (Fig. 15) | `h ⇝w fun(at){bt} → λu. ∃p,q,tbs(at){}. p = (u⇝w at); 𝒲bb⟦q = h[p]⟧; q ⇝w block{bt}` with `(bb,dr,vx) = w`, `𝒲∘⟦e⟧ = ⟨⟩`, `𝒲∙⟦e⟧ = e` |

Verification-mode rules (Fig. 16 `mfun`/`moftype` with `⟨ω⟩` effects, lines 585–612) and
`oftype` (`e1 ▷⟨ω⟩ e2 ⟶ e2[e1]`, "Outside verify") are **Essential-Verse**: Tier-2 audit
rows `Verify_MFun`, `Verify_MOFType`, `OFType` with `IsEssential = 1`, no kernel
constructor, no dialect lowering pattern in Timbda-0 (rejected by the legality checker).
`moftype`'s Core-Verse fragment (`u ⇝w t1 ▷ t2` desugarings, lines 602–609) is deferred
to the Essential tier boundary; `typeof` in the Timbda-0 AST (PLAN § 4.1) is the runtime
projection of `▷` and gets a kernel constructor only with M3's typeof typing rules
(Tier-3 stub in M0, admitted: "typeof e returns e's static type when defined").

## 4.1 Verification rules (Fig. 17, lines 638–664) and open lambdas (Fig. 18, lines
668–671) — Tier-2/3 audit records, `IsEssential = 1`, no M0 kernel constructor

These are the paper's **solver-side** rules (proof contexts `P ::= ∃X{hp}. Q`,
`Q ::= □ | e = Q | Q = e | e; Q | Q; e | e[Q] | Q[e] | iter(ic){Q}{e}`, line 638-639)
and its *incomplete* open-lambda rules. Timbda-0 implements neither `verify` nor open
lambdas (PLAN § 4.1: no `verify`/`olam` in the Core-Verse type/opcode table), so every
row below is an audit record with `IsEssential = 1` that the Core-Verse legality checker
**rejects**, and none gets a `Rew` constructor or a DRR pattern before M3+. They are
listed because the coverage claim is against the paper's rule list.

| Fig. 17 rule | Paper form (transcribed) | Tier | M0 status |
|---|---|---|---|
| solver | `verify(R; A){b} ⟶ ⟨⟩  if R; A ⊨ inconsistent` | 3 | no ctor; `Verify_Solver` row, admitted |
| v-val | `verify(R; A){B[v]} ⟶ ⟨⟩` | 3 | `Verify_Val` |
| v-choice | `verify(R; A){P[e1 e2]} ⟶ verify(R; A){P[e1]}; verify(R; A){P[e2]}` | 3 | `Verify_Choice` |
| v-fail | `verify(R; A){P[fail]} ⟶ ⟨⟩` | 3 | `Verify_Fail` |
| split-val | `verify(R; A){P[r = gv; e]} ⟶ verify(R; A, r = gv){P[e]}; verify(R; A, r ≠ gv){P[fail]}` | 3 | `Verify_SplitVal` |
| split-op | `verify(R; A){P[op[gv]]} ⟶ verify(R, r; A, r = op[gv]){P[r]}; verify(R; A, ¬op[gv]){P[fail]}  if r ∉ R` | 3 | `Verify_SplitOp` |
| split-tup | `verify(R; A){P[r = ⟨v1…vn⟩; e]} ⟶ verify(R, r1…rn; A, r = ⟨r1…rn⟩){P[r1 = v1; …; rn = vn; e]}; verify(R; A, r ≠ ⟨ , …, ⟩){P[fail]}` | 3 | `Verify_SplitTup` |
| split-app | `verify(R; A){P[f[gv]]} ⟶ verify(R, r; A, r = AP[f, gv]){P[r]}  if f ∈ R, r ∉ R` | 3 | `Verify_SplitApp` |
| split-appf | `verify(R; A){P[f[λx.e]]} ⟶ verify(R, r; A){P[r]}  if f ∈ R, r ∉ R` | 3 | `Verify_SplitAppF` |
| v-some | `verify(R; A){P[e1 ▷⟨ω⟩ e2]} ⟶ verify(R, r; A){∃x. x = e2[r]; P[x]}; verify(R; A){∃x. x = e2[r]; P[fail]};  if r ∉ R and fvs(v) # bvs(P)` | 3 | `Verify_Some` |

| Fig. 18 rule | Paper form (transcribed) | Tier | M0 status |
|---|---|---|---|
| u-olam | `olam(z1, v1) = olam(z2, v2); e ⟶ ∃z3. z1 = olam(z3, v2); z2 = olam(z3, v1); e` | 3 | `Olam_Unify` (paper marks Fig. 18 **incomplete**) |
| app-olam | `(olam(z, v1))[v2] ⟶ ∃x. x = z[v2]; x = v1[v2]; x` | 3 | `Olam_App` |
| exi-app | `∃z. e ⟶ e[(λx. ∃y. y)/z]  if z occurs in e only as z[v]` | 3 | `Olam_ExiApp` |

Skolem variables (`r`, `gv` = global value) have no kernel constructor: the kernel's
`Root`/`Val` taxonomy has no Skolem case, which is what makes these rows *records*
rather than rules (docs/RULES-AUDIT.md `IsEssential` column).

## 5. Strategy groups (Fig. 19–25 vocabulary)

The paper's strategy evaluation (Fig. 25 total order, lecture-3 notes) enumerates
group names; the kernel defines `StrategyGroup` (in `coq/Eval.v`) as a mirror of that
list, and the `pick_redex` evaluator selects by priority — the Gallina strategy
evaluator (PLAN § 4.4 / M0). Group list (transcribed from Fig. 25, with the paper's
`For`/`ForAll` spellings normalized to `ForS`/`ForU`/`AllS`/`AllU` per the rule names):

```
BindT, Bind, BindR, BindL, Match, If, IfS, ForS, ForU, ForAll, AllS, AllU,
Choice, Block, Return, BindSub, BindD, MatchD, MatchT, MatchR, MatchB, MatchL,
RetR, RetD, RetB, RetL, Norm, NormR, NormD, NormB, NormL
```

`TimbdaRule.strategy_group` (.td, M1) is declared `TimbdaStrategyGroup` and **must**
match the kernel group of the same rule; the M1 audit diff-checks both tables
(non-zero diff = milestone failure). Rules without a paper strategy entry (pure
normalization rewrites, e.g. Norm5's de-cluttering role) are assigned `Norm*` groups per
Fig. 25's last five entries.

## 6. Kernel semantics map (`coq/Semantics.v`)

The ctrees model (`E = EmptyFunctor` for M0; internal choice via `B2`; `ctree E B2
SResult`) — compositional evaluation, outcomes

```
SResult := ROk Sval | RFail | RStuck        (fail vs "goes wrong", Fig. 9 note lines 442–445)
Sval    := SUnit | SBool bool | SInt  Z | STup (list Sval) | SLam (Sval -> tree) | SDelay tree
```

- `Choice b1 b2` → `br2` (internal choice; candidates = internal branches, candidate
  *sets* recovered by the `gset` fold of `coq/Denotation.v` via ctrees `interp` — this is
  "candidate sets via ctrees internal choice", PLAN § 5.2).
- `Fail` → `ret RFail` (backtrackable); unification/primop violations → `ret RStuck`
  (aborts fallback — the `iter` rules observe the difference, mirroring the paper's
  fail-vs-stuck split).
- `Def` blocks: evaluate the bound expression (once), bind, evaluate the body; unused
  slot dropping is `RewGc1`'s subject.
- `Iter all/if/for` desugar exactly per the *kernel reading* of Fig. 13 rules and
  `mif`/`mall`/`mfor` (Fig. 14), with the `delay{e1}` / fallback structure; divergence is
  the ctrees cofix (`spin`).
- `Get/Put` (Verse refs): event carriers are defined (`GetEv/PutEv`) and interpreted
  through the ctrees event layer, but **no M0 rule or test exercises mutable state** —
  the mutable-heap candidate model lands at M4/T12 (`boost::context` only after the
  Gallina `Get/Put` model is validated here, PLAN § 4.4).

Per-rule theorem shape (M0): `RewSound_<Rule> : Rew <rule pattern> → ⟦e⟧ ≈ ⟦e'⟧` (ctrees
weak bisimulation). Tier-1 rules are fully proved; Tier-2 rules state the theorem with
the heap-evolution step admitted (`Admitted`, audit-visible). `KernelTest.v` proves the
M-algebra laws first (bind/br2 interchange = the M-algebra of choice: `bind (br2 t u) k
≈ br2 (bind t k) (bind u k)`, `br2` commutative/associative/idempotent — the ctrees
`SBisim`/`WBisim` laws), satisfying the M0 acceptance test "the kernel test proves the
M-algebra laws the first rules use".

## 7. Count for the M1 audit seed

Fig. 8–13 constructors in `coq/Rewriting.v`: Subst, Gc, PromoteL, PromoteR, HpAlpha,
LamAlpha, Seq, Norm1, Norm2, Norm3, Norm4, Norm5, Float (13); EqK1, EqK2, EqTup1,
EqTup2, EqFail (5); Add, Gt1, Gt2, IsInt1, IsInt2, Cons, DotDot (7); BetaL, BetaT,
BetaT0 (3); IterFail, IterChoice, IterIf, IterAll, IterFor (5) — **33 constructors**,
covering the paper's 26 named rules + 7 kernel-side extensions (BetaT0 base case,
PromoteR explicit, Gc split, cons2 primop helper recorded separately). Tier-2 matching
rows (Fig. 14–15: 18), Essential-verse rows (Fig. 16 + `oftype`: 4), verification rows
(Fig. 17: 10) and open-lambda rows (Fig. 18: 3) complete the audit corpus at **68
records** (the reconciliation of the earlier 55-record seed, which omitted Fig. 17–18, so
the M1 diff has a single arithmetic); every record maps to a `TimbdaRule`/`TimbdaExtern`
record in `dialect/Timbda.td` (M1), and the audit diff must be non-zero only for the
documented kernel-side extensions (this section is the record of that deviation —
PLAN § 11.2 deviation #2 is *rejected*, so extensions appear here, in the transcribed
paper list, as explicit constructor rows).

