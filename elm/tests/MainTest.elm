module MainTest exposing (blockDecoderSuite, canAddHeaderSuite, deviceSuite, suite)

import Expect
import Json.Decode as Decode
import Main exposing (Block, BlockContent(..), Device(..), blockDecoder, canAddHeader, deviceWidth, flagsDecoder)
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
