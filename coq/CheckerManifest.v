(* =====================================================================
    CheckerManifest.v - GENERATED FILE (M1 item 1, docs/PLAN.md sec. 5.0): the
    soundness REGISTRY for the 35 ctor rows - ctor name, audit tag, status, and
    the RewSound_* lemma names that row's kernel evidence consists of (a
    deferred row carries none, and no statement either - docs/RULES-AUDIT.md
    sec. 4).  Registry, not statements: per-row lemma statements are proof-side
    design (fuel budgets, closeV-wrapped hypotheses and added side conditions
    were measured against the discharged lemmas - docs/DESIGN-NOTES.md 13.12),
    so each proof lands in coq/Denotation.v while the audit lane re-checks this
    registry against both the records and the kernel lemma inventory.  This
    file carries no proof surface at all.  Regenerate:
        tblgen-rocq -gen-rocq-checker dialect/Timbda.td -o coq/CheckerManifest.v
    ===================================================================== *)

From Stdlib Require Import List Strings.String.
Import ListNotations.
Open Scope string_scope.

Definition soundness_manifest : list (string * string * string * list string) :=
  [("RewEqK1", "EqK1", "discharged", ["RewSound_EqK1"])
  ; ("RewEqK2", "EqK2", "discharged", ["RewSound_EqK2"])
  ; ("RewEqTup1", "EqTup1", "deferred", [])
  ; ("RewEqTup2", "EqTup2", "discharged", ["RewSound_EqTup2"])
  ; ("RewEqFail", "EqFail", "discharged", ["RewSound_EqFail"])
  ; ("RewAdd", "Add", "discharged", ["RewSound_Add"])
  ; ("RewGt1", "Gt1", "discharged", ["RewSound_Gt1"])
  ; ("RewGt2", "Gt2", "discharged", ["RewSound_Gt2"])
  ; ("RewIsInt1", "IsInt1", "discharged", ["RewSound_IsInt1"])
  ; ("RewIsInt2", "IsInt2", "discharged", ["RewSound_IsInt2"])
  ; ("RewCons", "Cons", "discharged", ["RewSound_Cons"])
  ; ("RewDotDot", "DotDot", "discharged", ["RewSound_DotDot"])
  ; ("RewPrim", "PrimSchema", "partial", ["RewSound_Prim1"; "RewSound_Prim2"])
  ; ("RewPrimFail", "PrimSchemaFail", "partial", ["RewSound_PrimFail1"; "RewSound_PrimFail2"])
  ; ("RewBetaL", "BetaL", "deferred", [])
  ; ("RewBetaT", "BetaT", "deferred", [])
  ; ("RewBetaT0", "BetaT0", "discharged", ["RewSound_BetaT0"])
  ; ("RewSeq", "Seq", "discharged", ["RewSound_Seq"])
  ; ("RewNorm1", "Norm1", "deferred", [])
  ; ("RewNorm2", "Norm2", "deferred", [])
  ; ("RewNorm3", "Norm3", "deferred", [])
  ; ("RewNorm4", "Norm4", "deferred", [])
  ; ("RewNorm5", "Norm5", "deferred", [])
  ; ("RewHpAlpha", "HpAlpha", "discharged", ["RewSound_HpAlpha"])
  ; ("RewLamAlpha", "LamAlpha", "discharged", ["RewSound_LamAlpha"])
  ; ("RewFloat", "Float", "deferred", [])
  ; ("RewSubst", "Subst", "deferred", [])
  ; ("RewGc1", "Gc1", "deferred", [])
  ; ("RewPromoteL", "PromoteL", "deferred", [])
  ; ("RewPromoteR", "PromoteR", "deferred", [])
  ; ("RewIterFail", "IterFail", "deferred", [])
  ; ("RewIterChoice", "IterChoice", "deferred", [])
  ; ("RewIterIf", "IterIf", "deferred", [])
  ; ("RewIterAll", "IterAll", "deferred", [])
  ; ("RewIterFor", "IterFor", "deferred", [])
  ].
