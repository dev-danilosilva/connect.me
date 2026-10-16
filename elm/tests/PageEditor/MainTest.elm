module PageEditor.MainTest exposing
    ( deviceSuite
    , suite
    )

import Expect
import Json.Decode as Decode
import PageEditor.Main exposing (Device(..), deviceWidth, flagsDecoder)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "flagsDecoder"
        [ test "decodes a complete flags object" <|
            \_ ->
                let
                    json =
                        """{"pageId": 1, "handle": "my-page", "title": "My Page", "username": "Ada", "csrfToken": "abc123", "apiBase": "/api/", "draftLayout": {"version": 1, "sections": []}}"""
                in
                Decode.decodeString flagsDecoder json
                    |> Result.map .handle
                    |> Expect.equal (Ok "my-page")
        , test "fails without a draft layout" <|
            \_ ->
                let
                    json =
                        """{"pageId": 1, "handle": "my-page", "title": "My Page", "username": "Ada", "csrfToken": "abc123", "apiBase": "/api/"}"""
                in
                Decode.decodeString flagsDecoder json
                    |> Result.toMaybe
                    |> Expect.equal Nothing
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
