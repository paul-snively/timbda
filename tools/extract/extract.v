(* Extraction driver for the differential harness (docs/PLAN.md sec. 6, "Gallina
   evaluator <-> C++ canonicalizer <-> augustss REPL oracle").

   This file is NOT part of the Timbda theory: it lives in tools/ on purpose so
   that `dune build` in coq/ - and with it the axiom/`Admitted` gate that
   flake.nix runs over the kernel - is untouched by harness scaffolding.

   On rocq 9.1 the extraction commands are a plugin, so the keyword `Extraction`
   is a syntax error ("illegal begin of vernac") until the theories file that
   carries `Declare ML Module "rocq-runtime.plugins.extraction"` is Required; the
   installed theories dir names it `Corelib.extraction` (measured: the glob file
   for lib/coq/theories/extraction/Extraction.v reads `FCorelib.extraction`).

   What is extracted is exactly the head-table cone of coq/Eval.v: the fuel-bounded
   normalizer, the head-redex selector, and the list of rows the head table can
   select.  `Print Assumptions` is printed first so the build log carries the
   axiom footprint of the extracted evaluator itself, not just of the kernel. *)

From Corelib.extraction Require Import Extraction.
Require Import Timbda.Syntax Timbda.Rewriting Timbda.Semantics Timbda.Eval.

Print Assumptions Timbda.Eval.norm.
Print Assumptions Timbda.Eval.head_redex.
Print Assumptions Timbda.Eval.selected_rows.

(* rocq 9.1 defaults the extraction output directory to the compilation dir and
   warns about it; say it explicitly so `rocq c` writes beside this file whatever
   `-output-directory` the caller passes. *)
Set Extraction Output Directory ".".

Extraction "timbda_eval.ml" Timbda.Eval.norm Timbda.Eval.head_redex Timbda.Eval.selected_rows.
