module PageEditor.EditorTest exposing (suite)

import Expect
import PageEditor.Editor as Editor exposing (Direction(..), HeroField(..), Msg(..), Slot(..))
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
                    , { id = "b", content = LinkTile { label = "B", url = "https://b.example", background = Video { src = "https://b.example/old.mp4", poster = "https://b.example/old.png" } } }
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

        , describe "uploads"
            (let
                videoSrc =
                    { sectionId = "links", itemId = "b", slot = VideoSrc }

                poster =
                    { sectionId = "links", itemId = "b", slot = VideoPoster }

                start =
                    Editor.init 42 layout

                oldVideo =
                    Video { src = "https://b.example/old.mp4", poster = "https://b.example/old.png" }

                backgroundOf id model =
                    model.layout.sections
                        |> List.concatMap
                            (\section ->
                                case section.content of
                                    Links tiles ->
                                        tiles

                                    _ ->
                                        []
                            )
                        |> List.filter (\tile -> tile.id == id)
                        |> List.map
                            (\tile ->
                                case tile.content of
                                    LinkTile link ->
                                        link.background
                            )
                        |> List.head
             in
             [ test "a started upload blocks saving until it finishes" <|
                \_ ->
                    let
                        uploading =
                            Editor.uploadStarted videoSrc start
                    in
                    Expect.equal
                        ( Editor.isUploading uploading
                        , Editor.isUploading (Editor.uploadFinished videoSrc (Ok "https://x.example/media/a.mp4") uploading)
                        )
                        ( True, False )
             , test "a finished upload fills its slot" <|
                \_ ->
                    start
                        |> Editor.uploadStarted videoSrc
                        |> Editor.uploadFinished videoSrc (Ok "https://x.example/media/a.mp4")
                        |> Editor.uploadStarted poster
                        |> Editor.uploadFinished poster (Ok "https://x.example/media/p.png")
                        |> backgroundOf "b"
                        |> Expect.equal (Just (Video { src = "https://x.example/media/a.mp4", poster = "https://x.example/media/p.png" }))
             , test "progress is tracked per slot" <|
                \_ ->
                    start
                        |> Editor.uploadStarted videoSrc
                        |> Editor.uploadProgress videoSrc 42
                        |> Editor.uploadsInProgress
                        |> Expect.equal [ videoSrc ]
             , test "a failed upload keeps the field and stops blocking saves" <|
                \_ ->
                    let
                        failed =
                            start
                                |> Editor.uploadStarted videoSrc
                                |> Editor.uploadFinished videoSrc (Err "Videos can be at most 20 MB.")
                    in
                    Expect.equal ( backgroundOf "b" failed, Editor.isUploading failed )
                        ( Just oldVideo, False )
             , test "an upload that finishes after the background changed kind is dropped" <|
                \_ ->
                    start
                        |> Editor.uploadStarted videoSrc
                        |> Editor.update (SetLinkBackground "links" "b" (Solid "#112233"))
                        |> Editor.uploadFinished videoSrc (Ok "https://x.example/media/a.mp4")
                        |> backgroundOf "b"
                        |> Expect.equal (Just (Solid "#112233"))
             , test "an upload that finishes after its tile was removed changes nothing" <|
                \_ ->
                    let
                        removed =
                            start
                                |> Editor.uploadStarted videoSrc
                                |> Editor.update (RemoveItem "links" "b")
                    in
                    Editor.uploadFinished videoSrc (Ok "https://x.example/media/a.mp4") removed
                        |> .layout
                        |> Expect.equal removed.layout
             , test "removing a tile drops its upload, so it no longer blocks saving" <|
                \_ ->
                    start
                        |> Editor.uploadStarted videoSrc
                        |> Editor.update (RemoveItem "links" "b")
                        |> Editor.isUploading
                        |> Expect.equal False
             , test "switching the background to another kind drops its upload" <|
                \_ ->
                    start
                        |> Editor.uploadStarted videoSrc
                        |> Editor.update (SetLinkBackground "links" "b" (Solid "#112233"))
                        |> Editor.isUploading
                        |> Expect.equal False
             , test "editing the same kind of background keeps its upload" <|
                \_ ->
                    start
                        |> Editor.uploadStarted videoSrc
                        |> Editor.update (SetLinkBackground "links" "b" (Video { src = "", poster = "https://b.example/p.png" }))
                        |> Editor.isUploading
                        |> Expect.equal True
             , test "a dropped upload that still answers changes nothing" <|
                \_ ->
                    let
                        switchedBack =
                            start
                                |> Editor.uploadStarted videoSrc
                                |> Editor.update (SetLinkBackground "links" "b" (Solid "#112233"))
                                |> Editor.update (SetLinkBackground "links" "b" oldVideo)
                    in
                    Editor.uploadFinished videoSrc (Err "Couldn't reach the server.") switchedBack
                        |> Expect.equal switchedBack
             , test "slots map to the server's kinds" <|
                \_ ->
                    List.map Editor.slotKind [ VideoSrc, VideoPoster, ImageSrc ]
                        |> Expect.equal [ "video", "image", "image" ]
             ]
            )
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
            , test "accepts localhost, which uploads return in development" <|
                \_ ->
                    List.map Editor.urlProblem
                        [ "http://localhost:8000/media/a.mp4", "http://localhost/media/a.mp4", "https://localhost" ]
                        |> Expect.equal [ Nothing, Nothing, Nothing ]
            ]
        ]
