module Lib.List exposing (at)

{-| List helpers missing from elm/core.
-}


{-| The item at a zero-based index, if there is one.

    at 1 [ "a", "b", "c" ] == Just "b"

    at 3 [ "a", "b", "c" ] == Nothing

-}
at : Int -> List a -> Maybe a
at index list =
    if index < 0 then
        Nothing

    else
        List.head (List.drop index list)
