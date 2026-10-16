port module PageEditor.Main exposing
    ( Device(..)
    , Flags
    , deviceWidth
    , flagsDecoder
    , main
    )

{-| The page editor program (/dashboard/pages/<handle>/edit/): a live preview
of the link page beside its editing controls.

Edits change the layout in PageEditor.Editor and show in the preview at
once. Save stores it as the page's draft (PUT /api/pages/<handle>/draft/);
Publish saves any unsaved changes, then makes the draft what visitors see
(POST /api/pages/<handle>/publish/).

Started from page\_editor.html with `Elm.PageEditor.Main.init`; compiled to
static/js/page\_editor.js.

-}

import Browser
import Html exposing (Html, a, button, div, h1, i, li, nav, ol, p, text)
import Html.Attributes exposing (attribute, class, classList, disabled, href, style, type_)
import Html.Events exposing (onClick)
import Http
import Json.Decode as Decode exposing (Decoder)
import PageEditor.Editor as Editor
import PageEditor.Layout as Layout exposing (Layout)
import PageEditor.Preview as Preview


{-| Tells page\_editor.html whether to warn before leaving the page.
-}
port setUnsavedChanges : Bool -> Cmd msg


type alias Flags =
    { pageId : Int
    , handle : String
    , title : String
    , username : String
    , csrfToken : String
    , apiBase : String
    , draftLayout : Layout
    , publishedLayout : Maybe Layout
    , idSeed : Int
    }


flagsDecoder : Decoder Flags
flagsDecoder =
    Decode.succeed Flags
        |> andMap (Decode.field "pageId" Decode.int)
        |> andMap (Decode.field "handle" Decode.string)
        |> andMap (Decode.field "title" Decode.string)
        |> andMap (Decode.field "username" Decode.string)
        |> andMap (Decode.field "csrfToken" Decode.string)
        |> andMap (Decode.field "apiBase" Decode.string)
        |> andMap (Decode.field "draftLayout" Layout.decoder)
        |> andMap (Decode.field "publishedLayout" (Decode.nullable Layout.decoder))
        |> andMap (Decode.field "idSeed" Decode.int)


andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    Decode.map2 (|>)


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
    , editor : Editor.Model

    -- The draft as the server last stored it.
    , saved : Layout

    -- What visitors see; Nothing until the page is first published.
    , published : Maybe Layout
    , request : Request
    }


type Request
    = Idle
    | Saving { sent : Layout, thenPublish : Bool }
    | Publishing
    | Failed String


type Msg
    = SetDevice Device
    | EditorMsg Editor.Msg
    | Save
    | Publish
    | GotSaved (Result String Layout)
    | GotPublished (Result String ())


init : Decode.Value -> ( Model, Cmd Msg )
init flagsJson =
    case Decode.decodeValue flagsDecoder flagsJson of
        Ok flags ->
            ( initialModel flags Phone, Cmd.none )

        Err _ ->
            ( initialModel
                { pageId = 0
                , handle = ""
                , title = ""
                , username = ""
                , csrfToken = ""
                , apiBase = ""
                , draftLayout = { sections = [] }
                , publishedLayout = Nothing
                , idSeed = 0
                }
                Desktop
            , Cmd.none
            )


initialModel : Flags -> Device -> Model
initialModel flags device =
    { flags = flags
    , device = device
    , editor = Editor.init flags.idSeed flags.draftLayout
    , saved = flags.draftLayout
    , published = flags.publishedLayout
    , request = Idle
    }


hasUnsavedChanges : Model -> Bool
hasUnsavedChanges model =
    model.editor.layout /= model.saved


isBusy : Model -> Bool
isBusy model =
    case model.request of
        Saving _ ->
            True

        Publishing ->
            True

        _ ->
            False


canSave : Model -> Bool
canSave model =
    hasUnsavedChanges model && not (isBusy model) && Editor.isValid model.editor.layout


canPublish : Model -> Bool
canPublish model =
    not (isBusy model)
        && Editor.isValid model.editor.layout
        && (hasUnsavedChanges model || model.published /= Just model.saved)


{-| Tells the page whenever the unsaved-changes state flips.
-}
updateAndGuard : Msg -> Model -> ( Model, Cmd Msg )
updateAndGuard msg model =
    let
        ( newModel, cmd ) =
            update msg model

        unsaved =
            hasUnsavedChanges newModel
    in
    if unsaved /= hasUnsavedChanges model then
        ( newModel, Cmd.batch [ cmd, setUnsavedChanges unsaved ] )

    else
        ( newModel, cmd )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SetDevice device ->
            ( { model | device = device }, Cmd.none )

        EditorMsg editorMsg ->
            ( { model | editor = Editor.update editorMsg model.editor }, Cmd.none )

        Save ->
            if canSave model then
                save False model

            else
                ( model, Cmd.none )

        Publish ->
            if not (canPublish model) then
                ( model, Cmd.none )

            else if hasUnsavedChanges model then
                save True model

            else
                publish model

        GotSaved result ->
            case ( result, model.request ) of
                ( Ok stored, Saving { sent, thenPublish } ) ->
                    let
                        editor =
                            model.editor

                        -- Take the server's cleaned copy (e.g. trimmed
                        -- labels), unless there were edits meanwhile.
                        savedModel =
                            { model
                                | saved = stored
                                , request = Idle
                                , editor =
                                    if editor.layout == sent then
                                        { editor | layout = stored }

                                    else
                                        editor
                            }
                    in
                    if thenPublish then
                        publish savedModel

                    else
                        ( savedModel, Cmd.none )

                ( Err message, _ ) ->
                    ( { model | request = Failed message }, Cmd.none )

                ( Ok _, _ ) ->
                    ( model, Cmd.none )

        GotPublished (Ok ()) ->
            ( { model | published = Just model.saved, request = Idle }, Cmd.none )

        GotPublished (Err message) ->
            ( { model | request = Failed message }, Cmd.none )


save : Bool -> Model -> ( Model, Cmd Msg )
save thenPublish model =
    ( { model | request = Saving { sent = model.editor.layout, thenPublish = thenPublish } }
    , Http.request
        { method = "PUT"
        , headers = [ Http.header "X-CSRFToken" model.flags.csrfToken ]
        , url = pageApiUrl model.flags "draft/"
        , body = Http.jsonBody (Layout.encode model.editor.layout)
        , expect = expectJson GotSaved Layout.decoder
        , timeout = Nothing
        , tracker = Nothing
        }
    )


publish : Model -> ( Model, Cmd Msg )
publish model =
    ( { model | request = Publishing }
    , Http.request
        { method = "POST"
        , headers = [ Http.header "X-CSRFToken" model.flags.csrfToken ]
        , url = pageApiUrl model.flags "publish/"
        , body = Http.emptyBody
        , expect = expectJson GotPublished (Decode.succeed ())
        , timeout = Nothing
        , tracker = Nothing
        }
    )


pageApiUrl : Flags -> String -> String
pageApiUrl flags path =
    flags.apiBase ++ "pages/" ++ flags.handle ++ "/" ++ path


{-| Like Http.expectJson, but failures become a message for the person
editing, using the server's validation errors when there are any.
-}
expectJson : (Result String a -> msg) -> Decoder a -> Http.Expect msg
expectJson toMsg decoder =
    Http.expectStringResponse toMsg
        (\response ->
            case response of
                Http.GoodStatus_ _ body ->
                    Decode.decodeString decoder body
                        |> Result.mapError (\_ -> "The server sent an unexpected response.")

                Http.BadStatus_ metadata body ->
                    Err (statusMessage metadata.statusCode body)

                Http.NetworkError_ ->
                    Err "Couldn't reach the server. Check your connection and try again."

                Http.Timeout_ ->
                    Err "The server took too long to answer. Try again."

                Http.BadUrl_ _ ->
                    Err "Couldn't send the request."
        )


statusMessage : Int -> String -> String
statusMessage status body =
    case status of
        400 ->
            case Decode.decodeString errorMessagesDecoder body of
                Ok (first :: _) ->
                    "Couldn't save: " ++ first

                _ ->
                    "Couldn't save: the page has invalid fields."

        403 ->
            "Your session has expired. Sign in again in another tab, then retry."

        _ ->
            "Something went wrong (error " ++ String.fromInt status ++ "). Try again."


{-| Every message in a DRF error body, however deeply nested.
-}
errorMessagesDecoder : Decoder (List String)
errorMessagesDecoder =
    Decode.oneOf
        [ Decode.map List.singleton Decode.string
        , Decode.map List.concat (Decode.list (Decode.lazy (\_ -> errorMessagesDecoder)))
        , Decode.map (List.concatMap Tuple.second) (Decode.keyValuePairs (Decode.lazy (\_ -> errorMessagesDecoder)))
        ]


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
            [ Preview.view model.editor.layout ]
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
        , Html.map EditorMsg (Editor.view model.editor)
        , viewActions model
        ]


viewActions : Model -> Html Msg
viewActions model =
    let
        ( status, isError ) =
            case model.request of
                Saving _ ->
                    ( "Saving…", False )

                Publishing ->
                    ( "Publishing…", False )

                Failed message ->
                    ( message, True )

                Idle ->
                    if hasUnsavedChanges model then
                        if Editor.isValid model.editor.layout then
                            ( "Unsaved changes", False )

                        else
                            ( "Fix the highlighted fields to save", False )

                    else if model.published == Just model.saved then
                        ( "Published", False )

                    else if model.published == Nothing then
                        ( "Saved · not published yet", False )

                    else
                        ( "Saved · changes not published yet", False )
    in
    div [ class "editor-actions" ]
        [ p
            [ classList [ ( "editor-status", True ), ( "editor-status-error", isError ) ]
            , attribute "role" "status"
            ]
            [ text status ]
        , div [ class "editor-action-buttons" ]
            [ button
                [ type_ "button"
                , class "btn btn-outlined editor-action"
                , disabled (not (canSave model))
                , onClick Save
                ]
                [ text "Save" ]
            , button
                [ type_ "button"
                , class "btn btn-filled editor-action"
                , disabled (not (canPublish model))
                , onClick Publish
                ]
                [ text "Publish" ]
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
        , update = updateAndGuard
        , view = view
        , subscriptions = \_ -> Sub.none
        }
