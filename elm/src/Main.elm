module Main exposing
    ( Block
    , BlockContent(..)
    , Device(..)
    , Flags
    , PageData
    , SocialIcon
    , blockDecoder
    , deviceWidth
    , flagsDecoder
    , main
    )

import Browser
import Html exposing (Html, button, div, text)
import Html.Attributes exposing (class, classList, style)
import Html.Events exposing (onClick)
import Http
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


type alias SocialIcon =
    { platform : String, url : String }


type BlockContent
    = LinkContent { label : String, url : String }
    | HeaderContent { displayName : String, bio : String, avatarUrl : String }
    | SocialIconsContent { icons : List SocialIcon }


type alias Block =
    { id : Int
    , position : Int
    , visible : Bool
    , content : BlockContent
    }


type alias PageData =
    { id : Int
    , handle : String
    , title : String
    , blocks : List Block
    }


socialIconDecoder : Decoder SocialIcon
socialIconDecoder =
    Decode.map2 SocialIcon
        (Decode.field "platform" Decode.string)
        (Decode.field "url" Decode.string)


contentDecoder : String -> Decoder BlockContent
contentDecoder blockType =
    case blockType of
        "link" ->
            Decode.map2 (\label url -> LinkContent { label = label, url = url })
                (Decode.field "label" Decode.string)
                (Decode.field "url" Decode.string)

        "header" ->
            Decode.map3
                (\displayName bio avatarUrl ->
                    HeaderContent { displayName = displayName, bio = bio, avatarUrl = avatarUrl }
                )
                (Decode.field "display_name" Decode.string)
                (Decode.oneOf [ Decode.field "bio" Decode.string, Decode.succeed "" ])
                (Decode.oneOf [ Decode.field "avatar_url" Decode.string, Decode.succeed "" ])

        "social_icons" ->
            Decode.map (\icons -> SocialIconsContent { icons = icons })
                (Decode.field "icons" (Decode.list socialIconDecoder))

        _ ->
            Decode.fail ("Unknown block_type: " ++ blockType)


blockDecoder : Decoder Block
blockDecoder =
    Decode.field "block_type" Decode.string
        |> Decode.andThen
            (\blockType ->
                Decode.map4
                    (\id position visible content -> Block id position visible content)
                    (Decode.field "id" Decode.int)
                    (Decode.field "position" Decode.int)
                    (Decode.field "visible" Decode.bool)
                    (Decode.field "data" (contentDecoder blockType))
            )


pageDecoder : Decoder PageData
pageDecoder =
    Decode.map4 PageData
        (Decode.field "id" Decode.int)
        (Decode.field "handle" Decode.string)
        (Decode.field "title" Decode.string)
        (Decode.field "blocks" (Decode.list blockDecoder))


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
    , page : Maybe PageData
    , device : Device
    , error : Maybe String
    }


type Msg
    = PageLoaded (Result Http.Error PageData)
    | SetDevice Device


fetchPage : Flags -> Cmd Msg
fetchPage flags =
    Http.get
        { url = flags.apiBase ++ "pages/" ++ flags.handle ++ "/"
        , expect = Http.expectJson PageLoaded pageDecoder
        }


init : Decode.Value -> ( Model, Cmd Msg )
init flagsJson =
    case Decode.decodeValue flagsDecoder flagsJson of
        Ok flags ->
            ( { flags = flags, page = Nothing, device = Desktop, error = Nothing }
            , fetchPage flags
            )

        Err _ ->
            ( { flags = Flags 0 "" "" "" ""
              , page = Nothing
              , device = Desktop
              , error = Just "Couldn't read page configuration."
              }
            , Cmd.none
            )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        PageLoaded (Ok pageData) ->
            ( { model | page = Just pageData }, Cmd.none )

        PageLoaded (Err _) ->
            ( { model | error = Just "Couldn't load this page. Try reloading." }, Cmd.none )

        SetDevice device ->
            ( { model | device = device }, Cmd.none )


viewDeviceButton : Device -> Device -> Html Msg
viewDeviceButton current device =
    button
        [ classList [ ( "device-button", True ), ( "device-button-active", current == device ) ]
        , onClick (SetDevice device)
        ]
        [ text (deviceLabel device) ]


deviceLabel : Device -> String
deviceLabel device =
    case device of
        Desktop ->
            "Desktop"

        Tablet ->
            "Tablet"

        Phone ->
            "Phone"


viewBlockPreview : Block -> Html Msg
viewBlockPreview block =
    case block.content of
        LinkContent { label } ->
            div [ class "preview-block preview-block-link" ] [ text label ]

        HeaderContent { displayName, bio } ->
            div [ class "preview-block preview-block-header" ]
                [ div [ class "preview-header-name" ] [ text displayName ]
                , div [ class "preview-header-bio" ] [ text bio ]
                ]

        SocialIconsContent { icons } ->
            div [ class "preview-block preview-block-social" ]
                (List.map (\icon -> Html.i [ class ("fa-brands fa-" ++ icon.platform) ] []) icons)


viewPreview : Model -> PageData -> Html Msg
viewPreview model pageData =
    div [ class "editor-preview-pane" ]
        [ div
            [ class "preview-frame"
            , style "width" (deviceWidth model.device |> Maybe.map (\w -> String.fromInt w ++ "px") |> Maybe.withDefault "100%")
            ]
            (List.map viewBlockPreview pageData.blocks)
        ]


viewControls : Model -> Html Msg
viewControls model =
    div [ class "editor-controls-pane" ]
        [ div [ class "device-switcher" ]
            [ viewDeviceButton model.device Desktop
            , viewDeviceButton model.device Tablet
            , viewDeviceButton model.device Phone
            ]
        ]


view : Model -> Html Msg
view model =
    case ( model.error, model.page ) of
        ( Just message, _ ) ->
            div [ class "editor-error" ] [ text message ]

        ( Nothing, Nothing ) ->
            div [ class "editor-loading" ] [ text "Loading..." ]

        ( Nothing, Just pageData ) ->
            div [ class "editor-shell" ] [ viewPreview model pageData, viewControls model ]


main : Program Decode.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
