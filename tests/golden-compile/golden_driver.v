(* golden_driver.v — the checks.golden-compile entry point (D4b).
   `rocq compile` on this file RE-CHECKS the whole chain (TimbdaTests.GoldenCompile
   and, through it, the Compile leaf and the kernel) and then evaluates
   `golden_lines`; render.py turns the display into the C source.

   The notation openings are MANDATORY FOR THE DISPLAY, measured 2026-11-27: the
   Compute result prints through the notations OPEN IN THIS FILE's scope - without
   `ListNotations` + `string_scope` the same list dumped as raw
   `String.String (Ascii.Ascii ...)` constructors and render.py (correctly)
   refused it.  No new math here — the verdicts, bodies, and refusals are pinned
   in GoldenCompile.v. *)
From Stdlib Require Import List String.
Import ListNotations.
Open Scope string_scope.

Require Import TimbdaTests.GoldenCompile.
Set Printing Depth 1000000.
Compute golden_lines.
