import Utility.Wrapper

main :: IO ()
main = runner fun

-- fun :: (Num alpha) => alpha -> alpha
fun :: String -> String
fun = id
