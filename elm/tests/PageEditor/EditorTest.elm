module PageEditor.EditorTest exposing (suite)

import Expect
import PageEditor.Editor as Editor exposing (Direction(..), HeroField(..), Msg(..))
import PageEditor.Layout exposing (Layout, Network(..), SectionContent(..), TileBackground(..), TileContent(..))
import Random
import Test exposing (Test, describe, test)


layout : Layout
layout =
    { sections =
        [ { id = "hero", content = Hero { displayName = "Ada", bio = "", imageUrl = "" } }
        , { id = "socials", content = Socials [] }
        , { id = "links"
          , content =
                Links
                    [ { id = "a", content = LinkTile { label = "A", url = "https://a.example", background = Solid "#000000" } }
                    , { id = "b", content = LinkTile { label = "B", url = "https://b.example", background = Solid "#000000" } }
                    ]
          }
        ]
    }


run : List Msg -> Layout
run msgs =
    List.foldl Editor.update (Editor.init 42 layout) msgs |> .layout


sectionIds : Layout -> List String
sectionIds =
    .sections >> List.map .id


tileLabels : Layout -> List String
tileLabels result =
    result.sections
        |> List.concatMap
            (\section ->
                case section.content of
                    Links tiles ->
                        List.map
                            (\tile ->
                                case tile.content of
                                    LinkTile link ->
                                        link.label
                            )
                            tiles

                    _ ->
                        []
            )


isUuid : String -> Bool
isUuid id =
    let
        groups =
            String.split "-" id
    in
    (List.map String.length groups == [ 8, 4, 4, 4, 12 ])
        && String.all (\c -> Char.isHexDigit c || c == '-') id
        && (String.slice 14 15 id == "4")
        && List.member (String.slice 19 20 id) [ "8", "9", "a", "b" ]


suite : Test
suite =
    describe "PageEditor.Editor"
        [ test "moves a section" <|
            \_ ->
                run [ MoveSection "links" Up ]
                    |> sectionIds
                    |> Expect.equal [ "hero", "links", "socials" ]
        , test "moves and removes tiles" <|
            \_ ->
                run [ MoveItem "links" "b" Up ]
                    |> tileLabels
                    |> Expect.equal [ "B", "A" ]
        , test "removes a tile" <|
            \_ ->
                run [ RemoveItem "links" "a" ]
                    |> tileLabels
                    |> Expect.equal [ "B" ]
        , test "edits the hero" <|
            \_ ->
                run [ SetHero "hero" DisplayName "Grace" ]
                    |> .sections
                    |> List.head
                    |> Maybe.map .content
                    |> Expect.equal (Just (Hero { displayName = "Grace", bio = "", imageUrl = "" }))
        , test "a new link opens, gets a fresh id and isn't valid until filled in" <|
            \_ ->
                let
                    model =
                        Editor.update (AddLink "links") (Editor.init 42 layout)
                in
                case model.openTile of
                    Just id ->
                        Expect.all
                            [ \_ -> Expect.equal True (isUuid id)
                            , \_ -> Expect.equal [ "A", "B", "" ] (tileLabels model.layout)
                            , \_ -> Expect.equal False (Editor.isValid model.layout)
                            ]
                            ()

                    Nothing ->
                        Expect.fail "the new link should be open"
        , test "new socials get distinct ids" <|
            \_ ->
                let
                    socials =
                        run [ AddSocial "socials", AddSocial "socials" ]
                            |> .sections
                            |> List.concatMap
                                (\section ->
                                    case section.content of
                                        Socials items ->
                                            List.map .id items

                                        _ ->
                                            []
                                )
                in
                case socials of
                    [ first, second ] ->
                        Expect.notEqual first second

                    _ ->
                        Expect.fail "expected two socials"
        , test "generates version 4 UUIDs" <|
            \_ ->
                Random.step (Random.list 50 Editor.idGenerator) (Random.initialSeed 7)
                    |> Tuple.first
                    |> List.all isUuid
                    |> Expect.equal True
        , test "the sample layout is valid" <|
            \_ -> Expect.equal True (Editor.isValid layout)
        , describe "urlProblem"
            [ test "accepts an https URL" <|
                \_ -> Expect.equal Nothing (Editor.urlProblem "https://example.com/a")
            , test "accepts an http URL" <|
                \_ -> Expect.equal Nothing (Editor.urlProblem "http://example.com")
            , test "asks for a URL when empty" <|
                \_ -> Expect.equal (Just "Enter a URL.") (Editor.urlProblem "")
            , test "asks for the scheme" <|
                \_ -> Expect.equal (Just "Start the URL with https://") (Editor.urlProblem "example.com")
            , test "rejects javascript URLs" <|
                \_ -> Expect.notEqual Nothing (Editor.urlProblem "javascript:alert(1)")
            , test "asks for a full host" <|
                \_ -> Expect.notEqual Nothing (Editor.urlProblem "https://example")
            ]
        ]
