module MainTest exposing
    ( blockDecoderSuite
    , canAddHeaderSuite
    , deviceSuite
    , moveBlockSuite
    , suite
    , updateBlockContentSuite
    )

import Expect
import Json.Decode as Decode
import Main exposing (Block, BlockContent(..), Device(..), blockDecoder, canAddHeader, deviceWidth, flagsDecoder, moveBlock, updateBlockContent)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "flagsDecoder"
        [ test "decodes a complete flags object" <|
            \_ ->
                let
                    json =
                        """{"pageId": 1, "handle": "my-page", "title": "My Page", "csrfToken": "abc123", "apiBase": "/api/"}"""
                in
                Decode.decodeString flagsDecoder json
                    |> Result.map .handle
                    |> Expect.equal (Ok "my-page")
        ]


deviceSuite : Test
deviceSuite =
    describe "deviceWidth"
        [ test "Desktop is unconstrained" <|
            \_ -> Expect.equal Nothing (deviceWidth Desktop)
        , test "Tablet is 768px" <|
            \_ -> Expect.equal (Just 768) (deviceWidth Tablet)
        , test "Phone is 390px" <|
            \_ -> Expect.equal (Just 390) (deviceWidth Phone)
        ]


blockDecoderSuite : Test
blockDecoderSuite =
    describe "blockDecoder"
        [ test "header block with missing bio and avatar_url still decodes, defaulting to empty strings" <|
            \_ ->
                let
                    json =
                        """{"block_type": "header", "id": 1, "position": 0, "visible": true, "data": {"display_name": "Jane"}}"""
                in
                Decode.decodeString blockDecoder json
                    |> Result.map .content
                    |> Expect.equal
                        (Ok (HeaderContent { displayName = "Jane", bio = "", avatarUrl = "" }))
        ]


canAddHeaderSuite : Test
canAddHeaderSuite =
    describe "canAddHeader"
        [ test "true when there is no header block yet" <|
            \_ ->
                Expect.equal True
                    (canAddHeader
                        [ Block 1 0 True (LinkContent { label = "x", url = "https://x.example" }) ]
                    )
        , test "false once a header block exists" <|
            \_ ->
                Expect.equal False
                    (canAddHeader
                        [ Block 1 0 True (HeaderContent { displayName = "Jane", bio = "", avatarUrl = "" }) ]
                    )
        ]


updateBlockContentSuite : Test
updateBlockContentSuite =
    describe "updateBlockContent"
        [ test "replaces a link block's label" <|
            \_ ->
                let
                    original =
                        LinkContent { label = "Old", url = "https://old.example" }
                in
                Expect.equal
                    (LinkContent { label = "New", url = "https://old.example" })
                    (updateBlockContent (\l -> { l | label = "New" }) identity identity original)
        ]


moveBlockSuite : Test
moveBlockSuite =
    describe "moveBlock"
        [ test "moving a block up swaps it with its predecessor" <|
            \_ ->
                let
                    blocks =
                        [ Block 1 0 True (LinkContent { label = "A", url = "https://a.example" })
                        , Block 2 1 True (LinkContent { label = "B", url = "https://b.example" })
                        ]
                in
                moveBlock 2 (-1) blocks
                    |> List.map .id
                    |> Expect.equal [ 2, 1 ]
        , test "moving the first block up is a no-op" <|
            \_ ->
                let
                    blocks =
                        [ Block 1 0 True (LinkContent { label = "A", url = "https://a.example" })
                        , Block 2 1 True (LinkContent { label = "B", url = "https://b.example" })
                        ]
                in
                moveBlock 1 (-1) blocks
                    |> List.map .id
                    |> Expect.equal [ 1, 2 ]
        ]
