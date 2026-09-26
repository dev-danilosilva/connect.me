module MainTest exposing (suite)

import Expect
import Json.Decode as Decode
import Main exposing (flagsDecoder)
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
