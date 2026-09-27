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
    , moveBlock
    , updateBlockContent
    )

import Array
import Browser
import Dict exposing (Dict)
import Html exposing (Html, button, div, text)
import Html.Attributes exposing (class, classList, style)
import Html.Events exposing (onClick)
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Process
import Task


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


updateBlockContent :
    ({ label : String, url : String } -> { label : String, url : String })
    -> ({ displayName : String, bio : String, avatarUrl : String } -> { displayName : String, bio : String, avatarUrl : String })
    -> ({ icons : List SocialIcon } -> { icons : List SocialIcon })
    -> BlockContent
    -> BlockContent
updateBlockContent editLink editHeader editSocial content =
    case content of
        LinkContent link ->
            LinkContent (editLink link)

        HeaderContent header ->
            HeaderContent (editHeader header)

        SocialIconsContent social ->
            SocialIconsContent (editSocial social)


moveBlock : Int -> Int -> List Block -> List Block
moveBlock blockId delta blocks =
    let
        ids =
            List.map .id blocks

        currentIndex =
            List.foldl
                (\( index, id ) found ->
                    if id == blockId then
                        Just index

                    else
                        found
                )
                Nothing
                (List.indexedMap Tuple.pair ids)

        newIndex =
            currentIndex |> Maybe.map (\i -> i + delta)
    in
    case ( currentIndex, newIndex ) of
        ( Just from, Just to ) ->
            if to < 0 || to >= List.length blocks then
                blocks

            else
                swapAt from to blocks

        _ ->
            blocks


swapAt : Int -> Int -> List a -> List a
swapAt i j list =
    let
        array =
            Array.fromList list

        vi =
            Array.get i array

        vj =
            Array.get j array
    in
    case ( vi, vj ) of
        ( Just a, Just b ) ->
            array |> Array.set i b |> Array.set j a |> Array.toList

        _ ->
            list


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
    , pendingSaves : Dict Int Int
    }


type Msg
    = PageLoaded (Result Http.Error PageData)
    | SetDevice Device
    | EditBlock Int BlockContent
    | Debounced Int Int
    | BlockSaved Int (Result Http.Error Block)
    | DeleteBlock Int
    | BlockDeleted Int (Result Http.Error ())
    | MoveBlock Int Int
    | Reordered (List Block) (Result Http.Error PageData)


fetchPage : Flags -> Cmd Msg
fetchPage flags =
    Http.get
        { url = flags.apiBase ++ "pages/" ++ flags.handle ++ "/"
        , expect = Http.expectJson PageLoaded pageDecoder
        }


contentEncoder : BlockContent -> Encode.Value
contentEncoder content =
    case content of
        LinkContent { label, url } ->
            Encode.object [ ( "label", Encode.string label ), ( "url", Encode.string url ) ]

        HeaderContent { displayName, bio, avatarUrl } ->
            Encode.object
                [ ( "display_name", Encode.string displayName )
                , ( "bio", Encode.string bio )
                , ( "avatar_url", Encode.string avatarUrl )
                ]

        SocialIconsContent { icons } ->
            Encode.object
                [ ( "icons"
                  , Encode.list
                        (\icon ->
                            Encode.object
                                [ ( "platform", Encode.string icon.platform )
                                , ( "url", Encode.string icon.url )
                                ]
                        )
                        icons
                  )
                ]


saveBlock : Flags -> Block -> Cmd Msg
saveBlock flags block =
    Http.request
        { method = "PATCH"
        , headers = [ Http.header "X-CSRFToken" flags.csrfToken ]
        , url = flags.apiBase ++ "pages/" ++ flags.handle ++ "/blocks/" ++ String.fromInt block.id ++ "/"
        , body = Http.jsonBody (Encode.object [ ( "data", contentEncoder block.content ) ])
        , expect = Http.expectJson (BlockSaved block.id) blockDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


deleteBlock : Flags -> Int -> Cmd Msg
deleteBlock flags blockId =
    Http.request
        { method = "DELETE"
        , headers = [ Http.header "X-CSRFToken" flags.csrfToken ]
        , url = flags.apiBase ++ "pages/" ++ flags.handle ++ "/blocks/" ++ String.fromInt blockId ++ "/"
        , body = Http.emptyBody
        , expect = Http.expectWhatever (BlockDeleted blockId)
        , timeout = Nothing
        , tracker = Nothing
        }


reorderBlocks : Flags -> List Block -> List Block -> Cmd Msg
reorderBlocks flags previousBlocks newBlocks =
    Http.request
        { method = "POST"
        , headers = [ Http.header "X-CSRFToken" flags.csrfToken ]
        , url = flags.apiBase ++ "pages/" ++ flags.handle ++ "/blocks/reorder/"
        , body = Http.jsonBody (Encode.object [ ( "block_ids", Encode.list (\b -> Encode.int b.id) newBlocks ) ])
        , expect = Http.expectJson (Reordered previousBlocks) pageDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


init : Decode.Value -> ( Model, Cmd Msg )
init flagsJson =
    case Decode.decodeValue flagsDecoder flagsJson of
        Ok flags ->
            ( { flags = flags, page = Nothing, device = Desktop, error = Nothing, pendingSaves = Dict.empty }
            , fetchPage flags
            )

        Err _ ->
            ( { flags = Flags 0 "" "" "" ""
              , page = Nothing
              , device = Desktop
              , error = Just "Couldn't read page configuration."
              , pendingSaves = Dict.empty
              }
            , Cmd.none
            )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        PageLoaded (Ok pageData) ->
            ( { model | page = Just pageData, error = Nothing }, Cmd.none )

        PageLoaded (Err _) ->
            ( { model | error = Just "Couldn't load this page. Try reloading." }, Cmd.none )

        SetDevice device ->
            ( { model | device = device }, Cmd.none )

        EditBlock blockId newContent ->
            let
                nextGeneration =
                    (Dict.get blockId model.pendingSaves |> Maybe.withDefault 0) + 1

                updatedPage =
                    Maybe.map
                        (\p ->
                            { p
                                | blocks =
                                    List.map
                                        (\b ->
                                            if b.id == blockId then
                                                { b | content = newContent }

                                            else
                                                b
                                        )
                                        p.blocks
                            }
                        )
                        model.page
            in
            ( { model | page = updatedPage, pendingSaves = Dict.insert blockId nextGeneration model.pendingSaves }
            , Process.sleep 500 |> Task.perform (\_ -> Debounced blockId nextGeneration)
            )

        Debounced blockId generation ->
            let
                currentGeneration =
                    Dict.get blockId model.pendingSaves |> Maybe.withDefault 0
            in
            if generation == currentGeneration then
                case model.page |> Maybe.andThen (\p -> List.filter (\b -> b.id == blockId) p.blocks |> List.head) of
                    Just block ->
                        ( model, saveBlock model.flags block )

                    Nothing ->
                        ( model, Cmd.none )

            else
                ( model, Cmd.none )

        BlockSaved _ (Ok _) ->
            ( { model | error = Nothing }, Cmd.none )

        BlockSaved _ (Err _) ->
            ( { model | error = Just "Couldn't save a change. Reload and try again." }, Cmd.none )

        DeleteBlock blockId ->
            ( { model | page = Maybe.map (\p -> { p | blocks = List.filter (\b -> b.id /= blockId) p.blocks }) model.page }
            , deleteBlock model.flags blockId
            )

        BlockDeleted _ (Ok ()) ->
            ( { model | error = Nothing }, Cmd.none )

        BlockDeleted _ (Err _) ->
            ( { model | error = Just "Couldn't delete that block. Reload to see the real state." }, Cmd.none )

        MoveBlock blockId delta ->
            case model.page of
                Just p ->
                    let
                        reordered =
                            moveBlock blockId delta p.blocks
                    in
                    ( { model | page = Just { p | blocks = reordered } }
                    , reorderBlocks model.flags p.blocks reordered
                    )

                Nothing ->
                    ( model, Cmd.none )

        Reordered _ (Ok _) ->
            -- The optimistic reorder in MoveBlock already applied the new
            -- order locally. Replacing model.page with the server's
            -- snapshot here would clobber any edit that's mid-debounce
            -- (the reorder round-trip typically finishes well before the
            -- 500ms edit debounce fires, so the snapshot can predate that
            -- edit) -- so on success we just keep the optimistic state.
            ( { model | error = Nothing }, Cmd.none )

        Reordered previousBlocks (Err _) ->
            ( { model
                | page = Maybe.map (\p -> { p | blocks = previousBlocks }) model.page
                , error = Just "Couldn't reorder blocks. Reverted."
              }
            , Cmd.none
            )


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


deleteButton : Block -> Html Msg
deleteButton block =
    button [ onClick (DeleteBlock block.id), class "delete-block-button" ]
        [ Html.i [ class "fa-solid fa-trash" ] [] ]


moveButtons : Block -> List (Html Msg)
moveButtons block =
    [ button [ onClick (MoveBlock block.id (-1)) ] [ Html.i [ class "fa-solid fa-arrow-up" ] [] ]
    , button [ onClick (MoveBlock block.id 1) ] [ Html.i [ class "fa-solid fa-arrow-down" ] [] ]
    ]


viewBlockEditor : Block -> Html Msg
viewBlockEditor block =
    case block.content of
        LinkContent link ->
            div [ class "block-editor" ]
                ([ Html.input
                    [ Html.Attributes.value link.label
                    , Html.Events.onInput
                        (\v -> EditBlock block.id (updateBlockContent (\l -> { l | label = v }) identity identity block.content))
                    ]
                    []
                 , Html.input
                    [ Html.Attributes.value link.url
                    , Html.Events.onInput
                        (\v -> EditBlock block.id (updateBlockContent (\l -> { l | url = v }) identity identity block.content))
                    ]
                    []
                 , deleteButton block
                 ]
                    ++ moveButtons block
                )

        HeaderContent header ->
            div [ class "block-editor" ]
                ([ Html.input
                    [ Html.Attributes.value header.displayName
                    , Html.Events.onInput
                        (\v -> EditBlock block.id (updateBlockContent identity (\h -> { h | displayName = v }) identity block.content))
                    ]
                    []
                 , Html.textarea
                    [ Html.Attributes.value header.bio
                    , Html.Events.onInput
                        (\v -> EditBlock block.id (updateBlockContent identity (\h -> { h | bio = v }) identity block.content))
                    ]
                    []
                 , deleteButton block
                 ]
                    ++ moveButtons block
                )

        SocialIconsContent social ->
            div [ class "block-editor" ]
                (List.indexedMap
                    (\index icon ->
                        div [ class "social-icon-row" ]
                            [ Html.input
                                [ Html.Attributes.value icon.platform
                                , Html.Attributes.placeholder "platform (e.g. twitter)"
                                , Html.Events.onInput
                                    (\v ->
                                        EditBlock block.id
                                            (updateBlockContent identity
                                                identity
                                                (\s -> { s | icons = List.indexedMap (\i ic -> if i == index then { ic | platform = v } else ic) s.icons })
                                                block.content
                                            )
                                    )
                                ]
                                []
                            , Html.input
                                [ Html.Attributes.value icon.url
                                , Html.Events.onInput
                                    (\v ->
                                        EditBlock block.id
                                            (updateBlockContent identity
                                                identity
                                                (\s -> { s | icons = List.indexedMap (\i ic -> if i == index then { ic | url = v } else ic) s.icons })
                                                block.content
                                            )
                                    )
                                ]
                                []
                            ]
                    )
                    social.icons
                    ++ [ button
                            [ onClick
                                (EditBlock block.id
                                    (updateBlockContent identity
                                        identity
                                        (\s -> { s | icons = s.icons ++ [ SocialIcon "" "" ] })
                                        block.content
                                    )
                                )
                            ]
                            [ text "Add icon" ]
                       , deleteButton block
                       ]
                    ++ moveButtons block
                )


viewPreview : Model -> PageData -> Html Msg
viewPreview model pageData =
    div [ class "editor-preview-pane" ]
        [ div
            [ class "preview-frame"
            , style "width" (deviceWidth model.device |> Maybe.map (\w -> String.fromInt w ++ "px") |> Maybe.withDefault "100%")
            ]
            (List.map viewBlockPreview pageData.blocks)
        ]


viewControls : Model -> PageData -> Html Msg
viewControls model pageData =
    div [ class "editor-controls-pane" ]
        [ div [ class "device-switcher" ]
            [ viewDeviceButton model.device Desktop
            , viewDeviceButton model.device Tablet
            , viewDeviceButton model.device Phone
            ]
        , div [ class "block-list" ] (List.map viewBlockEditor pageData.blocks)
        ]


view : Model -> Html Msg
view model =
    case model.page of
        Just pageData ->
            div [ class "editor-root" ]
                (List.filterMap identity
                    [ Maybe.map viewErrorBanner model.error
                    , Just (div [ class "editor-shell" ] [ viewPreview model pageData, viewControls model pageData ])
                    ]
                )

        Nothing ->
            case model.error of
                Just message ->
                    div [ class "editor-error" ] [ text message ]

                Nothing ->
                    div [ class "editor-loading" ] [ text "Loading..." ]


viewErrorBanner : String -> Html Msg
viewErrorBanner message =
    div [ class "editor-error-banner" ] [ text message ]


main : Program Decode.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }
