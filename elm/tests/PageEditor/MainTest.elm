module PageEditor.MainTest exposing
    ( deviceSuite
    , suite
    , uploadSuite
    )

import Expect
import Json.Decode as Decode
import PageEditor.Main exposing (Device(..), deviceWidth, flagsDecoder, uploadErrorMessage)
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "flagsDecoder"
        [ test "decodes a complete flags object" <|
            \_ ->
                let
                    json =
                        """{"pageId": 1, "handle": "my-page", "title": "My Page", "username": "Ada", "csrfToken": "abc123", "apiBase": "/api/", "draftLayout": {"version": 1, "sections": []}, "publishedLayout": null, "idSeed": 42}"""
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


uploadSuite : Test
uploadSuite =
    describe "uploadErrorMessage"
        [ test "shows the server's message as it is" <|
            \_ ->
                uploadErrorMessage 400 """{"file": ["Videos can be at most 20 MB."]}"""
                    |> Expect.equal "Videos can be at most 20 MB."
        , test "explains nginx's 413, which has no JSON body" <|
            \_ ->
                uploadErrorMessage 413 "<html><body>413 Request Entity Too Large</body></html>"
                    |> Expect.equal "That file is too big. Videos can be at most 20 MB."
        , test "asks to sign in again on 403" <|
            \_ ->
                uploadErrorMessage 403 ""
                    |> Expect.equal "Your session has expired. Sign in again in another tab, then retry."
        , test "falls back to a generic message" <|
            \_ ->
                uploadErrorMessage 500 ""
                    |> Expect.equal "Couldn't upload the file (error 500). Try again."
        ]
