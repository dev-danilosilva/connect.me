module Lib.List exposing (at, moveWhere)

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


{-| Moves the first item matching the predicate by `offset` places (-1 is
one place earlier), swapping it with the item there. Unchanged if no item
matches or the move would leave the list.

    moveWhere ((==) "b") -1 [ "a", "b", "c" ] == [ "b", "a", "c" ]

    moveWhere ((==) "c") 1 [ "a", "b", "c" ] == [ "a", "b", "c" ]

-}
moveWhere : (a -> Bool) -> Int -> List a -> List a
moveWhere isItem offset list =
    case findIndex isItem list of
        Nothing ->
            list

        Just from ->
            let
                to =
                    from + offset
            in
            case ( at from list, at to list ) of
                ( Just item, Just other ) ->
                    List.indexedMap
                        (\index x ->
                            if index == from then
                                other

                            else if index == to then
                                item

                            else
                                x
                        )
                        list

                _ ->
                    list


findIndex : (a -> Bool) -> List a -> Maybe Int
findIndex isItem list =
    list
        |> List.indexedMap Tuple.pair
        |> List.filter (Tuple.second >> isItem)
        |> List.head
        |> Maybe.map Tuple.first
