-- Timbda-0 golden harness stub (M-1). The differential triangle
-- (Gallina evaluator vs. C++ canonicalizer vs. Haskell tester) lands at M-2+.
normalize :: String -> String
normalize = unlines . fmap (unwords . words) . filter (not . null) . lines

main :: IO ()
main = do
  src <- readFile "golden.hs.input"
  putStr (normalize src)
