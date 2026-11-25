//===- TimbdaRocqGen.cpp - the tblgen-rocq backend (docs/PLAN.md sec. 2) --===//
//
// The Coq-side generator of the five-artifact contract (PLAN sec. 2), M1 item 1
// (PLAN sec. 5.0): the `Rew` constructors of the kernel are GENERATED from the
// TimbdaRuleRecord `coq*` fields in dialect/TimbdaRules.td (fields transcribed
// by tools/rules-coqctor.py; docs/DESIGN-NOTES.md sec. 13.10 records the
// toolchain decision).  coq/RewRules.v is the artifact; checks.tblgen-rocq-
// golden regenerates it and byte-diffs against the committed file, and
// tools/rules-audit.py asserts ctor-equality between this output and the
// record fields, so "generated, not hand-glued" is gate evidence.
//
// Modes (the PLAN sec. 2 artifact families):
//   -gen-rocq-rules    coq/RewRules.v: the Rew surface (Inductive Rew in
//                      TimbdaRuleGenOrder group order + the fixed
//                      rw_step/rewrites context-closure epilogue).
//   -gen-rocq-ast      coq/RuleAst.v: the eval-side rule AST surface -
//                      `Inductive RuleID` in TimbdaRuleAstOrder group order +
//                      `selected_rows` derived from the records' rank fields
//                      (replaces the hand-glued block retired from coq/Eval.v).
//   -gen-rocq-checker  coq/CheckerManifest.v: the soundness registry (per-rule
//                      lemma inventory + status as Coq data). Deliberately a
//                      registry, not lemma statements: measured against the 19
//                      discharged RewSound_* lemmas, the statement text is
//                      proof-side design (per-row fuel budgets, closeV-wrapped
//                      hypotheses, added side conditions), and a deferred row
//                      carries no statement by kernel policy
//                      (docs/RULES-AUDIT.md sec. 4; docs/DESIGN-NOTES.md 13.12).
//   -gen-pdll-tests    tests/lit/pdll/<ctor>.check: one FileCheck skeleton per
//                      DRR ctor row (PLAN sec. 2 artifact 3), asserting exactly
//                      what the record derives of the mlir-tblgen rewriter
//                      output: struct name, root op "timbda."+ops[0], and the
//                      populateWithGenerated entry.
// A mode that is not implemented must refuse, never emit a skeleton - an
// honest refusal keeps the golden lane's "byte-identical regeneration" claim
// meaningful for what it does cover.
//
// Toolchain (DESIGN-NOTES sec. 13.10, probes p512/p513): the flake builds this
// on nixpkgs llvmPackages_23, whose dev output ships no MLIR TableGen library,
// so the backend parses through the classic llvm::TableGen API
// (TableGenParseFile + RecordKeeper).  ODS .td is plain TableGen syntax, so
// the parse of the real dialect/Timbda.td chain is identical; the bazel side
// keeps compiling the dialect's C++/DRR with mlir-tblgen, and generated text
// is the only cross-graph interface (PLAN sec. 6).
//
//===----------------------------------------------------------------------===//

#include <algorithm>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/InitLLVM.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/TableGen/Parser.h"
#include "llvm/TableGen/Record.h"

using namespace llvm;

static StringRef ProgramName = "tblgen-rocq";

static void usage() {
  errs() << "usage: " << ProgramName
         << " -gen-rocq-rules|-gen-rocq-ast|-gen-rocq-checker|-gen-pdll-tests"
            "|-gen-rocq-externs"
            " <input.td> [-o <output>]\n";
}

//===----------------------------------------------------------------------===//
// Record plumbing
//===----------------------------------------------------------------------===//

namespace {

struct RocqCtor {
  const Record *Rec = nullptr;
  std::string Name;    // ctor (the `ctor` field)
  std::string Tag;     // coqTag: the audit-tag name (ctor suffix and tag may
                       // differ - RewPrim carries tag PrimSchema)
  std::string Forall;  // coqForall; empty = no forall
  SmallVector<std::string, 4> Hyps;
  std::string Lhs, Rhs;
  std::string Fig;     // the record's `fig` field
  int Tier = 0;        // the record's `tier` field
  std::string PapForm;
  std::string KernelTag;  // the eval-side RuleID name (R_...); empty = no RuleID
  std::string Status;     // discharged | partial | deferred
  int Selected = 0;       // the `selected` flag
  int Rank = 0;           // selected_rows order; 0 = not selected
  std::vector<std::string> SoundLemmas;  // RewSound_* names this row's evidence
  std::string Pattern;    // "drr" <=> this row has a stock DRR rewriter
  std::vector<std::string> Ops;  // verse ops; ops[0] names the DRR root op
};

// Collapse whitespace runs.  tools/rules-coqctor.py stores the fields
// flattened; collapsing again makes this generator robust to hand edits of
// the .td and keeps its own output a function of content, not layout.
static std::string collapseWS(StringRef S) {
  std::string Out;
  bool InSpace = false;
  for (char C : S) {
    if (C == ' ' || C == '\t' || C == '\n' || C == '\r') {
      InSpace = true;
      continue;
    }
    if (InSpace && !Out.empty())
      Out += ' ';
    InSpace = false;
    Out += C;
  }
  return Out;
}

// Gather every TimbdaRuleRecord def that carries a ctor (the 35 rule-surface
// rows; the 37 non-ctor rows - deferred statements, extern call sites - emit
// nothing here).  Every ctor row must carry the full coq surface: a missing
// field is an error, not an empty constructor.
// (std::unordered_map, not StringMap: the keys are strings this function
// creates, and StringMap keys must outlive the value they index.)
static bool collectCtors(const RecordKeeper &Records,
                         std::unordered_map<std::string, RocqCtor> &Ctors) {
  for (const auto &KV : Records.getDefs()) {
    const Record *R = KV.second.get();
    if (!R->isSubClassOf("TimbdaRuleRecord"))
      continue;
    StringRef Name = R->getValueAsString("ctor");
    if (Name.empty())
      continue;
    RocqCtor C;
    C.Rec = R;
    C.Name = Name.str();
    C.Tag = collapseWS(R->getValueAsString("coqTag"));
    C.Forall = collapseWS(R->getValueAsString("coqForall"));
    for (StringRef H : R->getValueAsListOfStrings("coqHyps"))
      C.Hyps.push_back(collapseWS(H));
    C.Lhs = collapseWS(R->getValueAsString("coqLhs"));
    C.Rhs = collapseWS(R->getValueAsString("coqRhs"));
    C.Fig = collapseWS(R->getValueAsString("fig"));
    C.Tier = (int)R->getValueAsInt("tier");
    C.PapForm = collapseWS(R->getValueAsString("papForm"));
    C.KernelTag = collapseWS(R->getValueAsString("kernelTag"));
    C.Status = collapseWS(R->getValueAsString("status"));
    C.Selected = (int)R->getValueAsInt("selected");
    C.Rank = (int)R->getValueAsInt("rank");
    C.Pattern = collapseWS(R->getValueAsString("pattern"));
    for (StringRef L : R->getValueAsListOfStrings("soundLemmas"))
      C.SoundLemmas.push_back(collapseWS(L));
    for (StringRef O : R->getValueAsListOfStrings("ops"))
      C.Ops.push_back(collapseWS(O));
    if (C.Tag.empty() || C.Lhs.empty() || C.Rhs.empty() || C.Fig.empty() ||
        C.PapForm.empty()) {
      errs() << ProgramName << ": record " << R->getName() << " carries ctor "
             << C.Name << " with an empty coq surface field (coqTag/coqLhs/"
             << "coqRhs/fig/papForm); run tools/rules-coqctor.py\n";
      return true;
    }
    if (Ctors.count(C.Name)) {
      errs() << ProgramName << ": duplicate ctor '" << C.Name << "'\n";
      return true;
    }
    Ctors.insert({C.Name, std::move(C)});
  }
  if (Ctors.empty()) {
    errs() << ProgramName << ": no ctor-carrying TimbdaRuleRecord found in "
              "the input - refusing to emit an empty rule surface\n";
    return true;
  }
  return false;
}

// Walk TimbdaRuleGenOrder.groups: every ctor row must appear in exactly one
// group, and every group ctor must exist.  That is the coverage half of the
// M1 claim ("the records generate the ctor surface", PLAN sec. 5.0 item 1);
// the audit lane asserts the same partition from the Coq side.
static bool collectOrder(const RecordKeeper &Records,
                         const std::unordered_map<std::string, RocqCtor> &Ctors,
                         SmallVector<const Record *, 8> &Groups) {
  const Record *Order = Records.getDef("TimbdaRuleGenOrder");
  if (!Order) {
    errs() << ProgramName << ": TimbdaRuleGenOrder not found (run "
              "tools/rules-coqctor.py --apply)\n";
    return true;
  }
  std::unordered_set<std::string> Seen;
  for (StringRef GName : Order->getValueAsListOfStrings("groups")) {
    const Record *G = Records.getDef(GName);
    if (!G) {
      errs() << ProgramName << ": group '" << GName << "' has no def\n";
      return true;
    }
    if (!G->isSubClassOf("TimbdaRuleGroup")) {
      errs() << ProgramName << ": '" << GName << "' is not a "
                "TimbdaRuleGroup\n";
      return true;
    }
    for (StringRef C : G->getValueAsListOfStrings("ctors")) {
      if (!Ctors.count(C.str())) {
        errs() << ProgramName << ": group " << GName << " names ctor '" << C
               << "' with no TimbdaRuleRecord row\n";
        return true;
      }
      if (Seen.count(C.str())) {
        errs() << ProgramName << ": ctor '" << C << "' appears in two groups\n";
        return true;
      }
      Seen.insert(C.str());
    }
    Groups.push_back(G);
  }
  if (Seen.size() != Ctors.size()) {
    errs() << ProgramName << ": emission groups cover " << Seen.size()
           << " of " << Ctors.size() << " ctor rows\n";
    return true;
  }
  return false;
}

//===----------------------------------------------------------------------===//
// Emission
//===----------------------------------------------------------------------===//

// Greedy word wrap to `Width`, first line at column FirstIndent and
// continuation lines at ContIndent.  Columns are tracked by hand (Coq treats
// the resulting newlines as plain whitespace; the wrap only buys reviewable
// line shapes, and it is a pure function of the input, so regeneration is
// byte-stable for a byte-identical .td).
static void emitWrapped(raw_ostream &OS, StringRef Text, unsigned FirstIndent,
                        unsigned ContIndent, unsigned Width) {
  SmallVector<StringRef, 64> Words;
  Text.split(Words, ' ');
  OS.indent(FirstIndent);
  unsigned Col = FirstIndent;
  bool First = true;
  for (StringRef W : Words) {
    if (W.empty())
      continue;
    if (!First) {
      if (Col + 1 + W.size() > Width) {
        OS << '\n';
        OS.indent(ContIndent);
        Col = ContIndent;
      } else {
        OS << ' ';
        ++Col;
      }
    }
    OS << W;
    Col += W.size();
    First = false;
  }
  OS << '\n';
}

static void emitCtor(raw_ostream &OS, const RocqCtor &C) {
  std::string Sig = "| " + C.Name + " : ";
  if (!C.Forall.empty())
    Sig += "forall " + C.Forall + ",";
  emitWrapped(OS, Sig, 0, 4, 78);
  for (const std::string &H : C.Hyps)
    emitWrapped(OS, H + " ->", 4, 8, 78);
  emitWrapped(OS, "Rew " + C.Lhs + " " + C.Rhs, 4, 8, 78);
  emitWrapped(OS, "(* audit: " + C.Tag + " | fig:" + C.Fig + " | tier:" +
                      std::to_string(C.Tier) + " | " + C.PapForm + " *)",
              4, 8, 78);
}

static void emitGroupHeader(raw_ostream &OS, const Record *G) {
  std::string Text = "(* ";
  for (StringRef H : G->getValueAsListOfStrings("headerLines")) {
    if (Text.size() > 3)
      Text += ' ';
    Text += collapseWS(H);
  }
  Text += " *)";
  emitWrapped(OS, Text, 0, 3, 78);
}

static const char *Prologue = R"PRIOUE((* =====================================================================
    `Rew lhs rhs` : a Core-Verse one-step rewrite at the root of a term.
    It is a *data* type (not a Prop) so that a rule value carries the rule
    identity into the audit tables and into the soundness lemmas
    (`RewSound_<Rule>` in Denotation.v).  Context closure lives in `rw_step` /
    `rewrites` at the end of this file.

    Tier labels follow docs/VERSE-RULES.md and classify the *statement*: Tier 2 =
    the constructor's own statement needs the evolving-heap machinery the M0
    statements omit (promote-l/r's `hp[v/x]` sub-step, float's C-general form);
    Tier 1 = everything else.  Per-ctor proof status (discharged at M0 / deferred,
    with reason class) is the table in docs/RULES-AUDIT.md section 1: tier is not
    status, and a deferred row carries no statement rather than an admitted one.

    GENERATED FILE (M1 item 1, docs/PLAN.md sec. 5.0): every constructor below is
    emitted by dialect/tblgen-rocq -gen-rocq-rules from the TimbdaRuleRecord
    coq* fields of dialect/TimbdaRules.td (records + emission groups maintained
    by tools/rules-coqctor.py).  Regenerate with:
        nix build .#timbda-tblgen-rocq
        tblgen-rocq -gen-rocq-rules dialect/Timbda.td -o coq/RewRules.v
    checks.tblgen-rocq-golden byte-diffs this file against regeneration, and
    tools/rules-audit.py asserts every constructor equals its record fields;
    hand edits here are a gate failure, not a contribution.
    ===================================================================== *)

From Stdlib Require Import ZArith Bool List.
From Timbda Require Import Syntax Rewriting.
Import ListNotations.

)PRIOUE";

// The context-closure surface is not rule-derived (it is the paper's C[ ] /
// B[ ] machinery, one inductive plus one definition), so it is fixed text of
// the backend - the same contract the hand-glued file carried, moved here so
// the generated file states the whole rewriting step (docs/PLAN.md sec. 2).
// The -gen-rocq-externs mode (M4) covers the dcont side, not this.
static const char *Epilogue = R"EPILOGUE(
(* ---------- Context closure (the paper's C[ ] / block nesting) ----------
   A rewrite fires at any position reached through evaluation contexts C (Fig. 6
   line 351) or through block bodies.  Rules whose statement already embeds the
   context (subst's S, iter's B/C, promote's C) quantify it directly; the closure
   below supplies the remaining positions.  Rewriting *slot values* in place
   (the paper's `B[S ] b` / `lambda x.B[S ]` contexts, line 353-355) is the
   Subst-Deep Tier-2 row - deferred to M3, recorded in docs/RULES-AUDIT.md. *)
Inductive rw_step : Expr -> Expr -> Prop :=
| rw_here : forall lhs rhs, Rew lhs rhs -> rw_step lhs rhs
| rw_ctx  : forall k lhs rhs, rw_step lhs rhs -> rw_step (fillC k lhs) (fillC k rhs)
| rw_blk  : forall slots lhs rhs, rw_step lhs rhs -> rw_step (Block slots lhs) (Block slots rhs).

Definition rewrites (lhs rhs : Expr) : Prop := rw_step lhs rhs.
)EPILOGUE";

static bool parseTD(StringRef TDFile, RecordKeeper &Records) {
  auto MBOrErr = MemoryBuffer::getFile(TDFile);
  if (!MBOrErr) {
    errs() << ProgramName << ": cannot open " << TDFile << "\n";
    return true;
  }
  SourceMgr SM;
  SM.AddNewSourceBuffer(std::move(*MBOrErr), SMLoc());
  if (TableGenParseFile(SM, Records)) {
    errs() << ProgramName << ": tablegen parse failed\n";
    return true;
  }
  return false;
}

static std::unique_ptr<raw_fd_ostream> openOut(StringRef OutFile,
                                               raw_ostream *&OS) {
  OS = &outs();
  if (OutFile.empty())
    return nullptr;
  std::error_code EC;
  auto Out = std::make_unique<raw_fd_ostream>(OutFile, EC, sys::fs::OF_None);
  if (EC) {
    errs() << ProgramName << ": cannot open " << OutFile << ": "
           << EC.message() << "\n";
    return nullptr;
  }
  OS = Out.get();
  return Out;
}

static int genRules(StringRef TDFile, StringRef OutFile) {
  RecordKeeper Records;
  if (parseTD(TDFile, Records))
    return 1;

  std::unordered_map<std::string, RocqCtor> Ctors;
  if (collectCtors(Records, Ctors))
    return 1;
  SmallVector<const Record *, 8> Groups;
  if (collectOrder(Records, Ctors, Groups))
    return 1;

  raw_ostream *OS = nullptr;
  auto OSOut = openOut(OutFile, OS);
  if (!OSOut && !OutFile.empty())
    return 1;

  *OS << Prologue;
  *OS << "Inductive Rew : Expr -> Expr -> Type :=\n";
  unsigned Emitted = 0;
  for (const Record *G : Groups) {
    *OS << '\n';
    emitGroupHeader(*OS, G);
    for (StringRef Name : G->getValueAsListOfStrings("ctors"))
      emitCtor(*OS, Ctors.find(Name.str())->second);
    Emitted += G->getValueAsListOfStrings("ctors").size();
  }
  *OS << ".\n";
  *OS << Epilogue;
  OS->flush();

  errs() << ProgramName << ": -gen-rocq-rules emitted " << Emitted
         << " ctors from " << Groups.size() << " emission groups (of "
         << Ctors.size() << " ctor records)";
  if (!OutFile.empty())
    errs() << " -> " << OutFile;
  errs() << "\n";
  return 0;
}

//===----------------------------------------------------------------------===//
// -gen-rocq-ast: coq/RuleAst.v - the eval-side RuleID/selected_rows surface
//===----------------------------------------------------------------------===//

static const char *RuleAstPrologue = R"ASTEOF((* =====================================================================
    RuleAst.v - GENERATED FILE (M1 item 1, docs/PLAN.md sec. 5.0): the eval-side
    rule AST surface.  `RuleID` carries one constructor per distinct non-empty
    `kernelTag` field of the ctor rows in dialect/TimbdaRules.td, grouped in
    TimbdaRuleAstOrder order with the group comments the records carry;
    `selected_rows` lists the ctor rows flagged `selected` in `rank` order,
    deduplicated by kernelTag (the two SCHEMA rows share R_Prim / R_PrimFail).
    The hand-glued block this replaces was retired from coq/Eval.v.  Regenerate:
        tblgen-rocq -gen-rocq-ast dialect/Timbda.td -o coq/RuleAst.v
    checks.tblgen-rocq-golden byte-diffs this file against regeneration and
    tools/rules-audit.py section 3 asserts the record provenance; hand edits
    here are a gate failure, not a contribution.
    ===================================================================== *)

From Stdlib Require Import List.
Import ListNotations.
)ASTEOF";

static int genAst(StringRef TDFile, StringRef OutFile) {
  RecordKeeper Records;
  if (parseTD(TDFile, Records))
    return 1;
  std::unordered_map<std::string, RocqCtor> Ctors;
  if (collectCtors(Records, Ctors))
    return 1;

  const Record *Order = Records.getDef("TimbdaRuleAstOrder");
  if (!Order) {
    errs() << ProgramName << ": TimbdaRuleAstOrder not found (run "
              "tools/rules-coqctor.py)\n";
    return 1;
  }
  std::unordered_map<std::string, unsigned> TagCount;
  for (const auto &KV : Ctors)
    if (!KV.second.KernelTag.empty())
      TagCount[KV.second.KernelTag]++;

  SmallVector<const Record *, 8> Groups;
  std::unordered_set<std::string> Seen;
  for (StringRef GName : Order->getValueAsListOfStrings("groups")) {
    const Record *G = Records.getDef(GName);
    if (!G || !G->isSubClassOf("TimbdaRuleAstGroup")) {
      errs() << ProgramName << ": RuleID group '" << GName
             << "' missing or not a TimbdaRuleAstGroup\n";
      return 1;
    }
    for (StringRef Id : G->getValueAsListOfStrings("ruleIds")) {
      if (!TagCount.count(Id.str())) {
        errs() << ProgramName << ": RuleID '" << Id << "' names no kernelTag\n";
        return 1;
      }
      if (!Seen.insert(Id.str()).second) {
        errs() << ProgramName << ": RuleID '" << Id << "' in two groups\n";
        return 1;
      }
    }
    Groups.push_back(G);
  }
  if (Seen.size() != TagCount.size()) {
    errs() << ProgramName << ": RuleID groups cover " << Seen.size()
           << " of " << TagCount.size() << " distinct kernelTags\n";
    return 1;
  }

  SmallVector<const RocqCtor *, 32> Sel;
  for (const auto &KV : Ctors)
    if (KV.second.Selected)
      Sel.push_back(&KV.second);
  std::sort(Sel.begin(), Sel.end(),
            [](const RocqCtor *A, const RocqCtor *B) { return A->Rank < B->Rank; });
  std::unordered_set<std::string> SelSeen;
  SmallVector<std::string, 32> SelIds;
  for (const RocqCtor *C : Sel) {
    if (C->KernelTag.empty() || C->Rank <= 0) {
      errs() << ProgramName << ": selected ctor " << C->Name
             << " has no kernelTag/rank to select\n";
      return 1;
    }
    if (SelSeen.insert(C->KernelTag).second)
      SelIds.push_back(C->KernelTag);
  }

  raw_ostream *OS = nullptr;
  auto OSOut = openOut(OutFile, OS);
  if (!OSOut && !OutFile.empty())
    return 1;

  *OS << RuleAstPrologue << "\nInductive RuleID : Type :=\n";
  for (unsigned I = 0; I < Groups.size(); ++I) {
    const Record *G = Groups[I];
    auto Ids = G->getValueAsListOfStrings("ruleIds");
    std::string Comment = collapseWS(G->getValueAsString("comment"));
    std::string Line = "| ";
    for (unsigned J = 0; J < Ids.size(); ++J) {
      if (J)
        Line += " | ";
      Line += Ids[J];
      if (I + 1 == Groups.size() && J + 1 == Ids.size())
        Line += ".";  // the inductive terminator rides the last ctor
    }
    std::string Tail = Comment.empty() ? "" : "        (* " + Comment + " *)";
    if (Comment.empty() || Line.size() + Tail.size() <= 78) {
      *OS << Line << Tail << "\n";
    } else {
      emitWrapped(*OS, Line, 0, 2, 78);
      emitWrapped(*OS, "(* " + Comment + " *)", 2, 2, 78);
    }
  }
  *OS << "\n(* selected_rows: the ctor rows flagged `selected` in `rank` order,\n"
         "   deduplicated by kernelTag *)\n"
         "Definition selected_rows : list RuleID :=\n";
  std::string ListStr = "[";
  for (unsigned I = 0; I < SelIds.size(); ++I) {
    if (I)
      ListStr += ";";
    ListStr += " " + SelIds[I];
  }
  ListStr += "].";
  emitWrapped(*OS, ListStr, 2, 2, 78);
  OS->flush();

  errs() << ProgramName << ": -gen-rocq-ast emitted " << Seen.size()
         << " RuleIDs from " << Groups.size() << " groups; selected_rows has "
         << SelIds.size() << " entries";
  if (!OutFile.empty())
    errs() << " -> " << OutFile;
  errs() << "\n";
  return 0;
}

//===----------------------------------------------------------------------===//
// -gen-rocq-checker: coq/CheckerManifest.v - the soundness registry
//===----------------------------------------------------------------------===//

static const char *ManifestPrologue = R"MEOF((* =====================================================================
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
)MEOF";

static int genChecker(StringRef TDFile, StringRef OutFile) {
  RecordKeeper Records;
  if (parseTD(TDFile, Records))
    return 1;
  std::unordered_map<std::string, RocqCtor> Ctors;
  if (collectCtors(Records, Ctors))
    return 1;
  // Reuse the rules-side group validation: manifest order is the emission
  // order, and the same exact-coverage claim is checked the same way.
  SmallVector<const Record *, 8> Groups;
  if (collectOrder(Records, Ctors, Groups))
    return 1;

  for (const auto &KV : Ctors) {
    const RocqCtor &C = KV.second;
    unsigned N = C.SoundLemmas.size();
    bool ok = (C.Status == "discharged" && N == 1) ||
              (C.Status == "partial" && N == 2) ||
              (C.Status == "deferred" && N == 0);
    if (!ok) {
      errs() << ProgramName << ": ctor " << C.Name << " status '" << C.Status
             << "' inconsistent with " << N << " soundLemmas\n";
      return 1;
    }
    for (const std::string &L : C.SoundLemmas)
      if (!StringRef(L).starts_with("RewSound_") || L.find('"') != std::string::npos) {
        errs() << ProgramName << ": ctor " << C.Name << " carries lemma '" << L
               << "' outside the RewSound_* family (or quote-bearing)\n";
        return 1;
      }
  }

  raw_ostream *OS = nullptr;
  auto OSOut = openOut(OutFile, OS);
  if (!OSOut && !OutFile.empty())
    return 1;

  *OS << ManifestPrologue;
  unsigned Emitted = 0;
  for (const Record *G : Groups) {
    for (StringRef Name : G->getValueAsListOfStrings("ctors")) {
      const RocqCtor &C = Ctors.find(Name.str())->second;
      std::string Entry = "(\"" + C.Name + "\", \"" + C.Tag + "\", \"" +
                          C.Status + "\", [";
      for (unsigned I = 0; I < C.SoundLemmas.size(); ++I) {
        if (I)
          Entry += "; ";
        Entry += "\"" + C.SoundLemmas[I] + "\"";
      }
      Entry += "])";
      *OS << (Emitted == 0 ? "  [" : "  ; ") << Entry << "\n";
      ++Emitted;
    }
  }
  *OS << "  ].\n";
  OS->flush();

  errs() << ProgramName << ": -gen-rocq-checker emitted " << Emitted
         << " manifest entries";
  if (!OutFile.empty())
    errs() << " -> " << OutFile;
  errs() << "\n";
  return 0;
}

//===----------------------------------------------------------------------===//
// -gen-pdll-tests: tests/lit/pdll/<ctor>.check - the pdll lit-test skeletons
//===----------------------------------------------------------------------===//

// One FileCheck skeleton per DRR ctor row (docs/PLAN.md sec. 2 artifact 3).
// The assertions are exactly what the rule record can honestly predict of
// the mlir-tblgen -gen-rewriters output: the struct named after the ctor,
// the root-op string "timbda." + ops[0], and the populateWithGenerated
// entry.  The matcher internals (benefit deltas, attr constraints) are the
// pattern file's business (dialect/TimbdaPatterns.td) and get asserted only
// where the record genuinely derives them - see docs/DESIGN-NOTES.md 13.13.
static int genPdll(StringRef TDFile, StringRef OutDir) {
  RecordKeeper Records;
  if (parseTD(TDFile, Records))
    return 1;
  std::unordered_map<std::string, RocqCtor> Ctors;
  if (collectCtors(Records, Ctors))
    return 1;
  SmallVector<const Record *, 8> Groups;
  if (collectOrder(Records, Ctors, Groups))
    return 1;
  if (OutDir.empty()) {
    errs() << ProgramName << ": -gen-pdll-tests needs -o <output-dir>\n";
    return 1;
  }
  if (sys::fs::create_directories(OutDir)) {
    errs() << ProgramName << ": cannot create output dir " << OutDir << "\n";
    return 1;
  }

  unsigned Emitted = 0;
  for (const Record *G : Groups) {
    for (StringRef Name : G->getValueAsListOfStrings("ctors")) {
      const RocqCtor &C = Ctors.find(Name.str())->second;
      if (C.Pattern != "drr")
        continue;
      if (C.Ops.empty()) {
        errs() << ProgramName << ": drr ctor " << C.Name
               << " has no ops[0] to name the root op\n";
        return 1;
      }
      std::string Root = "timbda." + C.Ops[0];
      std::string Path = (OutDir + "/" + C.Name + ".check").str();
      std::error_code EC;
      raw_fd_ostream Out(Path, EC, sys::fs::OF_None);
      if (EC) {
        errs() << ProgramName << ": cannot open " << Path << ": "
               << EC.message() << "\n";
        return 1;
      }
      Out << "; GENERATED FILE (M1 item 2, docs/PLAN.md sec. 5.0): the pdll\n"
             "; lit-test skeleton for ctor row "
          << C.Name << " (audit tag " << C.Tag << ", fig " << C.Fig
          << ") in dialect/TimbdaRules.td.  %timbda_drr_inc is the\n"
             "; bazel mlir-tblgen -gen-rewriters output over TimbdaPatterns.td,\n"
             "; sha256-attested by checks.bazel-native-tests.  Regenerate all\n"
             "; skeletons:\n"
             ";     tblgen-rocq -gen-pdll-tests dialect/Timbda.td -o tests/lit/pdll\n"
             "; checks.dialect-lit-tests byte-diffs this file against regeneration\n"
             "; and tools/rules-audit.py section 5 asserts the record provenance.\n"
             "\n"
             "; RUN: FileCheck --input-file=%timbda_drr_inc %s\n"
             "; CHECK-LABEL: struct "
          << C.Name << " : public ::mlir::RewritePattern {\n"
          << "; CHECK: ::mlir::RewritePattern(\"" << Root << "\",\n"
          << "; CHECK: patterns.add<" << C.Name << ">(patterns.getContext());\n";
      ++Emitted;
    }
  }

  errs() << ProgramName << ": -gen-pdll-tests emitted " << Emitted
         << " lit skeletons to " << OutDir << "\n";
  return 0;
}

} // end anonymous namespace

int main(int argc, char **argv) {
  InitLLVM X(argc, argv);
  if (argc > 0)
    ProgramName = sys::path::filename(argv[0]);

  StringRef Mode, TDFile, OutFile;
  for (int I = 1; I < argc; ++I) {
    StringRef A = argv[I];
    if (A == "-gen-rocq-rules" || A == "-gen-rocq-ast" ||
        A == "-gen-rocq-checker" || A == "-gen-pdll-tests" ||
        A == "-gen-rocq-externs") {
      if (!Mode.empty()) {
        errs() << ProgramName << ": multiple modes given\n";
        return 1;
      }
      Mode = A;
    } else if (A == "-o") {
      if (++I >= argc) {
        errs() << ProgramName << ": -o needs an argument\n";
        return 1;
      }
      OutFile = argv[I];
    } else if (!TDFile.empty()) {
      errs() << ProgramName << ": unknown argument '" << A << "'\n";
      return 1;
    } else {
      TDFile = A;
    }
  }
  if (Mode.empty() || TDFile.empty()) {
    usage();
    return 1;
  }

  if (Mode == "-gen-rocq-rules")
    return genRules(TDFile, OutFile);
  if (Mode == "-gen-rocq-ast")
    return genAst(TDFile, OutFile);
  if (Mode == "-gen-rocq-checker")
    return genChecker(TDFile, OutFile);
  if (Mode == "-gen-pdll-tests")
    return genPdll(TDFile, OutFile);

  // -gen-rocq-externs is the ContextExtern family: registered, lands at M4
  // (docs/PLAN.md sec. 5.0 binding), refuses until then.
  errs() << ProgramName << ": " << Mode
         << " is registered but not implemented yet (-gen-rocq-externs ships "
            "with the ContextExtern record family at M4, docs/PLAN.md sec. 5.0)"
            ".  Refusing to emit anything.\n";
  return 2;
}
