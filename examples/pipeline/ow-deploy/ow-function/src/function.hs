import Utility.Wrapper

main :: IO ()
main = runner fun

fun :: (Num alpha) => (alpha, alpha) -> (alpha, alpha)
fun = id
