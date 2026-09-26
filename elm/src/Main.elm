module Main exposing (Flags, flagsDecoder, main)

import Browser
import Html exposing (Html, div, text)
import Json.Decode as Decode exposing (Decoder)


type alias Flags =
    { pageId : Int
    , handle : String
    , title : String
    , csrfToken : String
    , apiBase : String
    }


flagsDecoder : Decoder Flags
flagsDecoder =
    Decode.map5 Flags
        (Decode.field "pageId" Decode.int)
        (Decode.field "handle" Decode.string)
        (Decode.field "title" Decode.string)
        (Decode.field "csrfToken" Decode.string)
        (Decode.field "apiBase" Decode.string)


type alias Model =
    { flags : Flags }


type Msg
    = NoOp


init : Decode.Value -> ( Model, Cmd Msg )
init flagsJson =
    case Decode.decodeValue flagsDecoder flagsJson of
        Ok flags ->
            ( { flags = flags }, Cmd.none )

        Err _ ->
            ( { flags = Flags 0 "" "" "" "" }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update _ model =
    ( model, Cmd.none )


view : Model -> Html Msg
view model =
    div [] [ text ("Loading " ++ model.flags.title ++ "...") ]


main : Program Decode.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
