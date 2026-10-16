module PageEditor.LayoutTest exposing (suite)

import Expect
import Json.Decode as Decode
import PageEditor.Layout as Layout exposing (Network(..), SectionContent(..), TileBackground(..), TileContent(..))
import Test exposing (Test, describe, test)


sample : String
sample =
    """
    {"version": 1, "sections": [
      {"id": "s1", "type": "hero", "displayName": "Ada", "bio": "Hi", "imageUrl": ""},
      {"id": "s2", "type": "socials", "items": [
        {"id": "i1", "network": "github", "url": "https://github.com/ada"}
      ]},
      {"id": "s3", "type": "links", "items": [
        {"id": "i2", "type": "link", "label": "Call", "url": "https://a.example/",
         "background": {"type": "solid", "color": "#4c1d95"}},
        {"id": "i3", "type": "link", "label": "Gallery", "url": "https://b.example/",
         "background": {"type": "image", "url": "https://b.example/i.jpg"}},
        {"id": "i4", "type": "link", "label": "Talk", "url": "https://c.example/",
         "background": {"type": "video", "src": "https://c.example/v.mp4", "poster": "https://c.example/p.jpg"}}
      ]}
    ]}
    """


{-| The sample with one string replaced, to break it in a single place.
-}
sampleWith : String -> String -> String
sampleWith old new =
    String.replace old new sample


suite : Test
suite =
    describe "PageEditor.Layout"
        [ test "decodes sections and tiles in order" <|
            \_ ->
                Decode.decodeString Layout.decoder sample
                    |> Result.map (.sections >> List.map .content)
                    |> Expect.equal
                        (Ok
                            [ Hero { displayName = "Ada", bio = "Hi", imageUrl = "" }
                            , Socials [ { id = "i1", network = GitHub, url = "https://github.com/ada" } ]
                            , Links
                                [ { id = "i2", content = LinkTile { label = "Call", url = "https://a.example/", background = Solid "#4c1d95" } }
                                , { id = "i3", content = LinkTile { label = "Gallery", url = "https://b.example/", background = Image "https://b.example/i.jpg" } }
                                , { id = "i4", content = LinkTile { label = "Talk", url = "https://c.example/", background = Video { src = "https://c.example/v.mp4", poster = "https://c.example/p.jpg" } } }
                                ]
                            ]
                        )
        , test "encoding then decoding gives the same layout" <|
            \_ ->
                case Decode.decodeString Layout.decoder sample of
                    Ok layout ->
                        Decode.decodeValue Layout.decoder (Layout.encode layout)
                            |> Expect.equal (Ok layout)

                    Err error ->
                        Expect.fail (Decode.errorToString error)
        , test "rejects other versions" <|
            \_ ->
                Decode.decodeString Layout.decoder (sampleWith "\"version\": 1" "\"version\": 2")
                    |> Result.toMaybe
                    |> Expect.equal Nothing
        , test "rejects gradient backgrounds" <|
            \_ ->
                Decode.decodeString Layout.decoder (sampleWith "\"type\": \"solid\", \"color\"" "\"type\": \"gradient\", \"color\"")
                    |> Result.toMaybe
                    |> Expect.equal Nothing
        , test "rejects unknown section types" <|
            \_ ->
                Decode.decodeString Layout.decoder (sampleWith "\"type\": \"socials\"" "\"type\": \"gallery\"")
                    |> Result.toMaybe
                    |> Expect.equal Nothing
        , test "rejects unknown tile types" <|
            \_ ->
                Decode.decodeString Layout.decoder (sampleWith "\"type\": \"link\", \"label\": \"Call\"" "\"type\": \"spotify\", \"label\": \"Call\"")
                    |> Result.toMaybe
                    |> Expect.equal Nothing
        , test "maps networks to their icon and label" <|
            \_ ->
                ( Layout.networkIcon X, Layout.networkLabel X )
                    |> Expect.equal ( "fa-brands fa-x-twitter", "X" )
        ]
