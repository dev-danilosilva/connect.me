module Lib.ListTest exposing (atSuite, moveWhereSuite)

import Expect
import Fuzz
import Lib.List
import Test exposing (Test, describe, fuzz, fuzz2, test)


atSuite : Test
atSuite =
    describe "Lib.List.at"
        [ test "first item" <|
            \_ -> Expect.equal (Just "a") (Lib.List.at 0 [ "a", "b", "c" ])
        , test "last item" <|
            \_ -> Expect.equal (Just "c") (Lib.List.at 2 [ "a", "b", "c" ])
        , test "one past the end is Nothing" <|
            \_ -> Expect.equal Nothing (Lib.List.at 3 [ "a", "b", "c" ])
        , test "negative index is Nothing" <|
            \_ -> Expect.equal Nothing (Lib.List.at -1 [ "a", "b", "c" ])
        , test "empty list is Nothing" <|
            \_ -> Expect.equal Nothing (Lib.List.at 0 [])
        , fuzz2 (Fuzz.intRange 0 30) (Fuzz.list Fuzz.int) "is Just exactly when the index is in range" <|
            \index list ->
                Expect.equal (index < List.length list) (Lib.List.at index list /= Nothing)
        , fuzz (Fuzz.intRange 0 50) "finds every index of a list of indexes" <|
            \n ->
                let
                    indexes =
                        List.range 0 n
                in
                Expect.equal (List.map Just indexes) (List.map (\i -> Lib.List.at i indexes) indexes)
        ]


moveWhereSuite : Test
moveWhereSuite =
    describe "Lib.List.moveWhere"
        [ test "moves an item one place earlier" <|
            \_ -> Expect.equal [ "b", "a", "c" ] (Lib.List.moveWhere ((==) "b") -1 [ "a", "b", "c" ])
        , test "moves an item one place later" <|
            \_ -> Expect.equal [ "a", "c", "b" ] (Lib.List.moveWhere ((==) "b") 1 [ "a", "b", "c" ])
        , test "leaves the first item when moving earlier" <|
            \_ -> Expect.equal [ "a", "b", "c" ] (Lib.List.moveWhere ((==) "a") -1 [ "a", "b", "c" ])
        , test "leaves the last item when moving later" <|
            \_ -> Expect.equal [ "a", "b", "c" ] (Lib.List.moveWhere ((==) "c") 1 [ "a", "b", "c" ])
        , test "leaves the list when nothing matches" <|
            \_ -> Expect.equal [ "a", "b" ] (Lib.List.moveWhere ((==) "z") 1 [ "a", "b" ])
        , fuzz (Fuzz.list Fuzz.int) "keeps every item" <|
            \list ->
                Expect.equal (List.sort list)
                    (List.sort (Lib.List.moveWhere (\x -> modBy 2 x == 0) 1 list))
        ]
