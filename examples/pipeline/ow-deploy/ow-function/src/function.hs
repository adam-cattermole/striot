import Utility.Wrapper

main :: IO ()
main = runner fun

fun :: (Floating alpha) => [alpha] -> [alpha]
fun = map (+100)
