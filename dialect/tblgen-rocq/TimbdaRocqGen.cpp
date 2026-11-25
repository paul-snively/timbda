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
//   -gen-rocq-rules    implemented: the RewRules.v rule surface (Inductive Rew
//                      in TimbdaRuleGenOrder group order + the fixed
//                      rw_step/rewrites context-closure epilogue).
//   -gen-rocq-ast      registered, refuses: not implemented until M1 item 1
//                      completion (the checked-syntax artifact).
//   -gen-rocq-checker  registered, refuses: not implemented until the M2 T4
//                      wiring moves the checker statements into records.
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
         << " -gen-rocq-rules|-gen-rocq-ast|-gen-rocq-checker <input.td>"
            " [-o <output>]\n";
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

static int genRules(StringRef TDFile, StringRef OutFile) {
  auto MBOrErr = MemoryBuffer::getFile(TDFile);
  if (!MBOrErr) {
    errs() << ProgramName << ": cannot open " << TDFile << "\n";
    return 1;
  }
  SourceMgr SM;
  SM.AddNewSourceBuffer(std::move(*MBOrErr), SMLoc());
  RecordKeeper Records;
  if (TableGenParseFile(SM, Records)) {
    errs() << ProgramName << ": tablegen parse failed\n";
    return 1;
  }

  std::unordered_map<std::string, RocqCtor> Ctors;
  if (collectCtors(Records, Ctors))
    return 1;
  SmallVector<const Record *, 8> Groups;
  if (collectOrder(Records, Ctors, Groups))
    return 1;

  std::unique_ptr<raw_fd_ostream> OSOut;
  raw_ostream *OS = &outs();
  if (!OutFile.empty()) {
    std::error_code EC;
    OSOut = std::make_unique<raw_fd_ostream>(OutFile, EC, sys::fs::OF_None);
    if (EC) {
      errs() << ProgramName << ": cannot open " << OutFile << ": "
             << EC.message() << "\n";
      return 1;
    }
    OS = OSOut.get();
  }

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

} // end anonymous namespace

int main(int argc, char **argv) {
  InitLLVM X(argc, argv);
  if (argc > 0)
    ProgramName = sys::path::filename(argv[0]);

  StringRef Mode, TDFile, OutFile;
  for (int I = 1; I < argc; ++I) {
    StringRef A = argv[I];
    if (A == "-gen-rocq-rules" || A == "-gen-rocq-ast" ||
        A == "-gen-rocq-checker") {
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

  // Registered-but-unimplemented modes refuse loudly (see the header note).
  errs() << ProgramName << ": " << Mode
         << " is registered but not implemented yet (docs/PLAN.md sec. 5.0:"
         << " -gen-rocq-ast lands with the M1 item 1 completion, "
            "-gen-rocq-checker with the M2 T4 wiring).  Refusing to emit "
            "anything.\n";
  return 2;
}
