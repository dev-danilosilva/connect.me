module PageEditor.Main exposing
    ( Device(..)
    , Flags
    , deviceWidth
    , flagsDecoder
    , main
    )

{-| The page editor program (/dashboard/pages/<handle>/edit/): a live preview
of the link page beside its editing controls.

Started from page\_editor.html with `Elm.PageEditor.Main.init`; compiled to
static/js/page\_editor.js.

-}

import Browser
import Html exposing (Html, a, button, div, h1, i, li, nav, ol, p, text)
import Html.Attributes exposing (attribute, class, classList, href, style)
import Html.Events exposing (onClick)
import Json.Decode as Decode exposing (Decoder)
import PageEditor.Layout as Layout exposing (Layout)
import PageEditor.Preview as Preview


type alias Flags =
    { pageId : Int
    , handle : String
    , title : String
    , username : String
    , csrfToken : String
    , apiBase : String
    , draftLayout : Layout
    }


flagsDecoder : Decoder Flags
flagsDecoder =
    Decode.map7 Flags
        (Decode.field "pageId" Decode.int)
        (Decode.field "handle" Decode.string)
        (Decode.field "title" Decode.string)
        (Decode.field "username" Decode.string)
        (Decode.field "csrfToken" Decode.string)
        (Decode.field "apiBase" Decode.string)
        (Decode.field "draftLayout" Layout.decoder)


type Device
    = Desktop
    | Tablet
    | Phone


deviceWidth : Device -> Maybe Int
deviceWidth device =
    case device of
        Desktop ->
            Nothing

        Tablet ->
            Just 768

        Phone ->
            Just 390


type alias Model =
    { flags : Flags
    , device : Device
    }


type Msg
    = SetDevice Device


init : Decode.Value -> ( Model, Cmd Msg )
init flagsJson =
    case Decode.decodeValue flagsDecoder flagsJson of
        Ok flags ->
            ( { flags = flags, device = Phone }, Cmd.none )

        Err _ ->
            ( { flags =
                    { pageId = 0
                    , handle = ""
                    , title = ""
                    , username = ""
                    , csrfToken = ""
                    , apiBase = ""
                    , draftLayout = { sections = [] }
                    }
              , device = Desktop
              }
            , Cmd.none
            )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SetDevice device ->
            ( { model | device = device }, Cmd.none )


viewDeviceButton : Device -> Device -> Html Msg
viewDeviceButton current device =
    button
        [ classList [ ( "device-button", True ), ( "device-button-active", current == device ) ]
        , onClick (SetDevice device)
        ]
        [ i [ class ("fa-solid " ++ deviceIcon device), attribute "aria-hidden" "true" ] []
        , text (deviceLabel device)
        ]


deviceIcon : Device -> String
deviceIcon device =
    case device of
        Desktop ->
            "fa-desktop"

        Tablet ->
            "fa-tablet-screen-button"

        Phone ->
            "fa-mobile-screen-button"


deviceLabel : Device -> String
deviceLabel device =
    case device of
        Desktop ->
            "Desktop"

        Tablet ->
            "Tablet"

        Phone ->
            "Phone"


viewPreview : Model -> Html Msg
viewPreview model =
    div [ class "editor-preview-pane" ]
        [ div
            [ class "preview-frame"
            , style "width" (deviceWidth model.device |> Maybe.map (\w -> String.fromInt w ++ "px") |> Maybe.withDefault "100%")
            ]
            [ Preview.view model.flags.draftLayout ]
        ]


viewControls : Model -> Html Msg
viewControls model =
    div [ class "editor-controls-pane" ]
        [ viewBreadcrumbs model.flags
        , div [ class "editor-header" ]
            [ h1 [ class "editor-title" ] [ text model.flags.title ]
            , p [ class "editor-slug" ] [ text ("mylinks.app/" ++ model.flags.handle) ]
            , div [ class "device-switcher" ]
                [ viewDeviceButton model.device Desktop
                , viewDeviceButton model.device Tablet
                , viewDeviceButton model.device Phone
                ]
            ]
        ]


viewBreadcrumbs : Flags -> Html Msg
viewBreadcrumbs flags =
    let
        separator =
            li [ class "breadcrumb-separator", attribute "aria-hidden" "true" ]
                [ i [ class "fa-solid fa-chevron-right" ] [] ]
    in
    nav [ class "editor-breadcrumbs", attribute "aria-label" "Breadcrumb" ]
        [ ol []
            [ li [ class "breadcrumb-home" ]
                [ a [ href "/", attribute "aria-label" "Home" ]
                    [ i [ class "fa-solid fa-house", attribute "aria-hidden" "true" ] [] ]
                ]
            , separator
            , li [ class "breadcrumb-item" ] [ text flags.username ]
            , separator
            , li [ class "breadcrumb-item" ] [ a [ href "/dashboard/" ] [ text "Pages" ] ]
            , separator
            , li [ class "breadcrumb-item breadcrumb-current", attribute "aria-current" "page" ] [ text flags.title ]
            ]
        ]


view : Model -> Html Msg
view model =
    div
        [ class "editor-shell"
        ]
        [ viewPreview model
        , viewControls model
        ]


main : Program Decode.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
