module PageEditor.Editor exposing
    ( Direction(..)
    , HeroField(..)
    , Model
    , Msg(..)
    , Slot(..)
    , UploadState(..)
    , UploadTarget
    , acceptedTypes
    , idGenerator
    , init
    , isUploading
    , isValid
    , slotKind
    , update
    , uploadFinished
    , uploadKey
    , uploadProgress
    , uploadStarted
    , uploadsInProgress
    , urlProblem
    , view
    )

{-| The controls that edit a page's layout: one card per section, in the
layout's order, holding the fields of the section and its items.

Edits only change `layout` here; PageEditor.Main saves and publishes it.
Problems with a field (an incomplete URL, a missing label) are shown under
it, and `isValid` tells Main whether the layout can be saved. Django
validates again on save.

-}

import Dict exposing (Dict)
import Html exposing (Html, button, div, h2, i, input, label, li, option, p, section, select, span, text, textarea, ul)
import Html.Attributes exposing (attribute, class, classList, disabled, maxlength, placeholder, rows, selected, title, type_, value)
import Html.Events exposing (onClick, onInput)
import Lib.List
import PageEditor.Layout as Layout
    exposing
        ( HeroData
        , Layout
        , Link
        , Network(..)
        , Section
        , SectionContent(..)
        , Social
        , Tile
        , TileBackground(..)
        , TileContent(..)
        )
import Random


type alias Model =
    { layout : Layout

    -- The link tile whose fields are shown; the others are collapsed.
    , openTile : Maybe String

    -- For the ids of new items.
    , seed : Random.Seed

    -- Uploads in progress or failed, by uploadKey. PageEditor.Main sends
    -- the requests and reports back through uploadProgress/uploadFinished.
    , uploads : Dict String { target : UploadTarget, state : UploadState }
    }


init : Int -> Layout -> Model
init idSeed layout =
    { layout = layout
    , openTile = Nothing
    , seed = Random.initialSeed idSeed
    , uploads = Dict.empty
    }


{-| A background field a file can be uploaded into.
-}
type Slot
    = VideoSrc
    | VideoPoster
    | ImageSrc


type alias UploadTarget =
    { sectionId : String
    , itemId : String
    , slot : Slot
    }


type UploadState
    = Uploading Int
    | UploadFailed String


type Direction
    = Up
    | Down


type HeroField
    = DisplayName
    | Bio
    | ImageUrl


{-| Section and item messages carry the section's id, then the item's.
-}
type Msg
    = MoveSection String Direction
    | SetHero String HeroField String
    | AddSocial String
    | SetSocialNetwork String String Network
    | SetSocialUrl String String String
    | AddLink String
    | SetLinkLabel String String String
    | SetLinkUrl String String String
    | SetLinkBackground String String TileBackground
    | MoveItem String String Direction
    | RemoveItem String String
    | ToggleTile String
      -- Handled by PageEditor.Main, which picks the file and uploads it.
    | RequestUpload UploadTarget



-- UPDATE


update : Msg -> Model -> Model
update msg model =
    apply msg model |> dropStaleUploads


apply : Msg -> Model -> Model
apply msg model =
    case msg of
        MoveSection sectionId direction ->
            let
                layout =
                    model.layout
            in
            { model | layout = { layout | sections = moveById sectionId direction layout.sections } }

        SetHero sectionId field newValue ->
            mapSection sectionId
                (\content ->
                    case content of
                        Hero hero ->
                            Hero (setHeroField field newValue hero)

                        other ->
                            other
                )
                model

        AddSocial sectionId ->
            let
                ( id, seed ) =
                    Random.step idGenerator model.seed
            in
            { model | seed = seed }
                |> mapSection sectionId (mapSocials (\socials -> socials ++ [ { id = id, network = Website, url = "" } ]))

        SetSocialNetwork sectionId itemId network ->
            mapSection sectionId (mapSocials (updateById itemId (\social -> { social | network = network }))) model

        SetSocialUrl sectionId itemId url ->
            mapSection sectionId (mapSocials (updateById itemId (\social -> { social | url = url }))) model

        AddLink sectionId ->
            let
                ( id, seed ) =
                    Random.step idGenerator model.seed

                tile =
                    { id = id
                    , content = LinkTile { label = "", url = "", background = Solid defaultTileColor }
                    }
            in
            { model | seed = seed, openTile = Just id }
                |> mapSection sectionId (mapTiles (\tiles -> tiles ++ [ tile ]))

        SetLinkLabel sectionId itemId newLabel ->
            mapSection sectionId (mapTiles (updateById itemId (mapLink (\link -> { link | label = newLabel })))) model

        SetLinkUrl sectionId itemId url ->
            mapSection sectionId (mapTiles (updateById itemId (mapLink (\link -> { link | url = url })))) model

        SetLinkBackground sectionId itemId background ->
            -- An edit clears the tile's failed uploads; ones in progress stay
            -- while the background is still of their kind (dropStaleUploads).
            { model | uploads = Dict.filter (\_ upload -> upload.target.itemId /= itemId || isInProgress upload.state) model.uploads }
                |> mapSection sectionId (mapTiles (updateById itemId (mapLink (\link -> { link | background = background }))))

        MoveItem sectionId itemId direction ->
            mapSection sectionId
                (\content ->
                    case content of
                        Socials socials ->
                            Socials (moveById itemId direction socials)

                        Links tiles ->
                            Links (moveById itemId direction tiles)

                        other ->
                            other
                )
                model

        RemoveItem sectionId itemId ->
            mapSection sectionId
                (\content ->
                    case content of
                        Socials socials ->
                            Socials (removeById itemId socials)

                        Links tiles ->
                            Links (removeById itemId tiles)

                        other ->
                            other
                )
                model

        RequestUpload _ ->
            model

        ToggleTile itemId ->
            { model
                | openTile =
                    if model.openTile == Just itemId then
                        Nothing

                    else
                        Just itemId
            }


defaultTileColor : String
defaultTileColor =
    "#4c1d95"



-- UPLOADS


uploadKey : UploadTarget -> String
uploadKey target =
    target.itemId ++ "/" ++ slotName target.slot


slotName : Slot -> String
slotName slot =
    case slot of
        VideoSrc ->
            "video-src"

        VideoPoster ->
            "video-poster"

        ImageSrc ->
            "image-src"


{-| The `kind` the upload endpoint checks the file against.
-}
slotKind : Slot -> String
slotKind slot =
    case slot of
        VideoSrc ->
            "video"

        _ ->
            "image"


{-| What the file picker offers; the server checks the bytes anyway.
-}
acceptedTypes : Slot -> List String
acceptedTypes slot =
    case slot of
        VideoSrc ->
            [ "video/mp4", "video/webm" ]

        _ ->
            [ "image/jpeg", "image/png", "image/webp" ]


{-| The Upload button's accessible name. It mustn't contain the field's
own label, or looking the field up by its label would also find the button.
-}
uploadLabel : Slot -> String
uploadLabel slot =
    case slot of
        VideoSrc ->
            "Upload a video file"

        VideoPoster ->
            "Upload a poster image"

        ImageSrc ->
            "Upload an image file"


isInProgress : UploadState -> Bool
isInProgress state =
    case state of
        Uploading _ ->
            True

        UploadFailed _ ->
            False


uploadStarted : UploadTarget -> Model -> Model
uploadStarted target model =
    { model | uploads = Dict.insert (uploadKey target) { target = target, state = Uploading 0 } model.uploads }


uploadProgress : UploadTarget -> Int -> Model -> Model
uploadProgress target percent model =
    { model
        | uploads =
            Dict.update (uploadKey target)
                (Maybe.map (\upload -> { upload | state = Uploading percent }))
                model.uploads
    }


{-| Puts an uploaded file's URL into its slot, if the tile still has a
background of that kind; or keeps the error to show under the field.
-}
uploadFinished : UploadTarget -> Result String String -> Model -> Model
uploadFinished target result model =
    case ( uploadState model target, result ) of
        ( Just (Uploading _), Ok url ) ->
            { model | uploads = Dict.remove (uploadKey target) model.uploads }
                |> mapSection target.sectionId
                    (mapTiles (updateById target.itemId (mapLink (\link -> { link | background = fillSlot target.slot url link.background }))))

        ( Just (Uploading _), Err message ) ->
            { model | uploads = Dict.insert (uploadKey target) { target = target, state = UploadFailed message } model.uploads }

        -- Dropped by dropStaleUploads; its tile has moved on.
        _ ->
            model


fillSlot : Slot -> String -> TileBackground -> TileBackground
fillSlot slot url background =
    case ( slot, background ) of
        ( VideoSrc, Video clip ) ->
            Video { clip | src = url }

        ( VideoPoster, Video clip ) ->
            Video { clip | poster = url }

        ( ImageSrc, Image _ ) ->
            Image url

        _ ->
            background


{-| Forgets uploads whose tile was removed or whose background is no longer
of their kind: nothing shows them any more, so they mustn't block saving.
PageEditor.Main cancels their requests.
-}
dropStaleUploads : Model -> Model
dropStaleUploads model =
    let
        fits upload =
            case ( upload.target.slot, linkBackground upload.target model.layout ) of
                ( VideoSrc, Just (Video _) ) ->
                    True

                ( VideoPoster, Just (Video _) ) ->
                    True

                ( ImageSrc, Just (Image _) ) ->
                    True

                _ ->
                    False
    in
    { model | uploads = Dict.filter (\_ upload -> fits upload) model.uploads }


linkBackground : UploadTarget -> Layout -> Maybe TileBackground
linkBackground target layout =
    layout.sections
        |> List.filter (\section -> section.id == target.sectionId)
        |> List.concatMap
            (\section ->
                case section.content of
                    Links tiles ->
                        tiles

                    _ ->
                        []
            )
        |> List.filter (\tile -> tile.id == target.itemId)
        |> List.map
            (\tile ->
                case tile.content of
                    LinkTile link ->
                        link.background
            )
        |> List.head


uploadsInProgress : Model -> List UploadTarget
uploadsInProgress model =
    Dict.values model.uploads
        |> List.filter (.state >> isInProgress)
        |> List.map .target


isUploading : Model -> Bool
isUploading model =
    not (List.isEmpty (uploadsInProgress model))


uploadState : Model -> UploadTarget -> Maybe UploadState
uploadState model target =
    Dict.get (uploadKey target) model.uploads |> Maybe.map .state


setHeroField : HeroField -> String -> HeroData -> HeroData
setHeroField field newValue hero =
    case field of
        DisplayName ->
            { hero | displayName = newValue }

        Bio ->
            { hero | bio = newValue }

        ImageUrl ->
            { hero | imageUrl = newValue }


mapSection : String -> (SectionContent -> SectionContent) -> Model -> Model
mapSection sectionId f model =
    let
        layout =
            model.layout
    in
    { model
        | layout =
            { layout | sections = updateById sectionId (\s -> { s | content = f s.content }) layout.sections }
    }


mapSocials : (List Social -> List Social) -> SectionContent -> SectionContent
mapSocials f content =
    case content of
        Socials socials ->
            Socials (f socials)

        other ->
            other


mapTiles : (List Tile -> List Tile) -> SectionContent -> SectionContent
mapTiles f content =
    case content of
        Links tiles ->
            Links (f tiles)

        other ->
            other


mapLink : (Link -> Link) -> Tile -> Tile
mapLink f tile =
    case tile.content of
        LinkTile link ->
            { tile | content = LinkTile (f link) }


updateById : String -> ({ a | id : String } -> { a | id : String }) -> List { a | id : String } -> List { a | id : String }
updateById id f =
    List.map
        (\item ->
            if item.id == id then
                f item

            else
                item
        )


moveById : String -> Direction -> List { a | id : String } -> List { a | id : String }
moveById id direction =
    Lib.List.moveWhere (\item -> item.id == id)
        (case direction of
            Up ->
                -1

            Down ->
                1
        )


removeById : String -> List { a | id : String } -> List { a | id : String }
removeById id =
    List.filter (\item -> item.id /= id)


{-| A random (version 4) UUID, the id format the spec requires.
-}
idGenerator : Random.Generator String
idGenerator =
    Random.list 32 (Random.int 0 15)
        |> Random.map
            (\digits ->
                let
                    hex =
                        digits
                            |> List.indexedMap
                                (\index digit ->
                                    -- The version nibble, then the variant bits.
                                    if index == 12 then
                                        4

                                    else if index == 16 then
                                        8 + modBy 4 digit

                                    else
                                        digit
                                )
                            |> List.map hexDigit
                            |> String.fromList
                in
                String.join "-"
                    [ String.slice 0 8 hex
                    , String.slice 8 12 hex
                    , String.slice 12 16 hex
                    , String.slice 16 20 hex
                    , String.slice 20 32 hex
                    ]
            )


hexDigit : Int -> Char
hexDigit digit =
    String.toList "0123456789abcdef"
        |> Lib.List.at digit
        |> Maybe.withDefault '0'



-- VALIDATION


{-| Why a URL can't be saved, if it can't. A quick check for the editor;
Django's validation on save is the authority.
-}
urlProblem : String -> Maybe String
urlProblem url =
    let
        afterScheme =
            if String.startsWith "https://" url then
                Just (String.dropLeft 8 url)

            else if String.startsWith "http://" url then
                Just (String.dropLeft 7 url)

            else
                Nothing

        host =
            Maybe.map (String.split "/" >> List.head >> Maybe.withDefault "") afterScheme
    in
    if String.isEmpty (String.trim url) then
        Just "Enter a URL."

    else
        case host of
            Nothing ->
                Just "Start the URL with https://"

            Just name ->
                -- localhost: uploads return the server's own URL, which is
                -- localhost in development.
                if (String.contains "." name || isLocalhost name) && not (String.contains " " url) then
                    Nothing

                else
                    Just "Enter a full URL, like https://example.com"


isLocalhost : String -> Bool
isLocalhost host =
    host == "localhost" || String.startsWith "localhost:" host


optionalUrlProblem : String -> Maybe String
optionalUrlProblem url =
    if String.isEmpty url then
        Nothing

    else
        urlProblem url


labelProblem : String -> Maybe String
labelProblem linkLabel =
    if String.isEmpty (String.trim linkLabel) then
        Just "Give the link a label."

    else
        Nothing


backgroundProblems : TileBackground -> List (Maybe String)
backgroundProblems background =
    case background of
        Solid _ ->
            []

        Image url ->
            [ urlProblem url ]

        Video clip ->
            [ urlProblem clip.src, urlProblem clip.poster ]


linkProblems : Link -> List (Maybe String)
linkProblems link =
    labelProblem link.label :: urlProblem link.url :: backgroundProblems link.background


{-| Whether every field of the layout can be saved.
-}
isValid : Layout -> Bool
isValid layout =
    layout.sections
        |> List.concatMap
            (\s ->
                case s.content of
                    Hero hero ->
                        [ optionalUrlProblem hero.imageUrl ]

                    Socials socials ->
                        List.map (.url >> urlProblem) socials

                    Links tiles ->
                        List.concatMap (\tile -> tileProblems tile) tiles
            )
        |> List.all ((==) Nothing)


tileProblems : Tile -> List (Maybe String)
tileProblems tile =
    case tile.content of
        LinkTile link ->
            linkProblems link



-- VIEW


view : Model -> Html Msg
view model =
    let
        count =
            List.length model.layout.sections
    in
    div [ class "editor-sections" ]
        (List.indexedMap (viewSection model count) model.layout.sections)


viewSection : Model -> Int -> Int -> Section -> Html Msg
viewSection model count index sectionData =
    let
        ( icon, heading, body ) =
            case sectionData.content of
                Hero hero ->
                    ( "fa-user", "Profile", viewHeroFields sectionData.id hero )

                Socials socials ->
                    ( "fa-share-nodes", "Social links", viewSocials sectionData.id socials )

                Links tiles ->
                    ( "fa-link", "Links", viewTiles model sectionData.id tiles )
    in
    section [ class "editor-section" ]
        [ div [ class "editor-section-header" ]
            [ h2 [ class "editor-section-title" ]
                [ i [ class ("fa-solid " ++ icon), attribute "aria-hidden" "true" ] []
                , text heading
                ]
            , div [ class "editor-row-actions" ]
                [ iconButton ("Move " ++ heading ++ " up") "fa-arrow-up" (index > 0) (MoveSection sectionData.id Up)
                , iconButton ("Move " ++ heading ++ " down") "fa-arrow-down" (index < count - 1) (MoveSection sectionData.id Down)
                ]
            ]
        , div [ class "editor-section-body" ] body
        ]


viewHeroFields : String -> HeroData -> List (Html Msg)
viewHeroFields sectionId hero =
    [ textField
        { label = "Name"
        , value = hero.displayName
        , placeholder = "Your name"
        , maxLength = 80
        , problem = Nothing
        , toMsg = SetHero sectionId DisplayName
        }
    , label [ class "editor-field" ]
        [ span [ class "editor-field-label" ] [ text "Bio" ]
        , textarea
            [ class "editor-input editor-textarea"
            , value hero.bio
            , placeholder "A line or two about you"
            , maxlength 300
            , rows 3
            , onInput (SetHero sectionId Bio)
            ]
            []
        ]
    , textField
        { label = "Cover image URL"
        , value = hero.imageUrl
        , placeholder = "https://… (optional)"
        , maxLength = 2000
        , problem = optionalUrlProblem hero.imageUrl
        , toMsg = SetHero sectionId ImageUrl
        }
    ]


viewSocials : String -> List Social -> List (Html Msg)
viewSocials sectionId socials =
    let
        count =
            List.length socials
    in
    [ if List.isEmpty socials then
        p [ class "editor-empty" ] [ text "No social links yet." ]

      else
        ul [ class "editor-items" ] (List.indexedMap (viewSocial sectionId count) socials)
    , addButton "Add social link" (AddSocial sectionId)
    ]


viewSocial : String -> Int -> Int -> Social -> Html Msg
viewSocial sectionId count index social =
    li [ class "editor-item" ]
        [ div [ class "editor-item-header" ]
            [ select
                [ class "editor-input editor-select"
                , attribute "aria-label" "Network"
                , onInput
                    (\name ->
                        SetSocialNetwork sectionId
                            social.id
                            (Layout.networkFromName name |> Maybe.withDefault social.network)
                    )
                ]
                (List.map
                    (\network ->
                        option [ value (Layout.networkName network), selected (network == social.network) ]
                            [ text (Layout.networkLabel network) ]
                    )
                    Layout.allNetworks
                )
            , itemActions (Layout.networkLabel social.network ++ " link") sectionId social.id index count
            ]
        , textField
            { label = "URL"
            , value = social.url
            , placeholder = "https://"
            , maxLength = 2000
            , problem = urlProblem social.url
            , toMsg = SetSocialUrl sectionId social.id
            }
        ]


viewTiles : Model -> String -> List Tile -> List (Html Msg)
viewTiles model sectionId tiles =
    let
        count =
            List.length tiles
    in
    [ if List.isEmpty tiles then
        p [ class "editor-empty" ] [ text "No links yet." ]

      else
        ul [ class "editor-items" ] (List.indexedMap (viewTile model sectionId count) tiles)
    , addButton "Add link" (AddLink sectionId)
    ]


viewTile : Model -> String -> Int -> Int -> Tile -> Html Msg
viewTile model sectionId count index tile =
    case tile.content of
        LinkTile link ->
            let
                isOpen =
                    model.openTile == Just tile.id

                name =
                    if String.isEmpty (String.trim link.label) then
                        "Untitled link"

                    else
                        link.label

                hasProblems =
                    List.any ((/=) Nothing) (linkProblems link)
            in
            li [ class "editor-item", classList [ ( "editor-item-open", isOpen ) ] ]
                [ div [ class "editor-item-header" ]
                    [ button
                        [ class "editor-item-toggle"
                        , type_ "button"
                        , attribute "aria-expanded"
                            (if isOpen then
                                "true"

                             else
                                "false"
                            )
                        , onClick (ToggleTile tile.id)
                        ]
                        [ i [ class "fa-solid fa-chevron-right editor-item-chevron", attribute "aria-hidden" "true" ] []
                        , span [ class "editor-item-title" ] [ text name ]
                        , if hasProblems && not isOpen then
                            i
                                [ class "fa-solid fa-circle-exclamation editor-item-warning"
                                , attribute "aria-label" "Has fields to fix"
                                , title "Has fields to fix"
                                ]
                                []

                          else
                            text ""
                        ]
                    , itemActions name sectionId tile.id index count
                    ]
                , if isOpen then
                    div [ class "editor-item-body" ] (viewLinkFields model sectionId tile.id link)

                  else
                    text ""
                ]


viewLinkFields : Model -> String -> String -> Link -> List (Html Msg)
viewLinkFields model sectionId itemId link =
    [ textField
        { label = "Label"
        , value = link.label
        , placeholder = "Read my latest essay"
        , maxLength = 80
        , problem = labelProblem link.label
        , toMsg = SetLinkLabel sectionId itemId
        }
    , textField
        { label = "URL"
        , value = link.url
        , placeholder = "https://"
        , maxLength = 2000
        , problem = urlProblem link.url
        , toMsg = SetLinkUrl sectionId itemId
        }
    , viewBackgroundFields model sectionId itemId link.background
    ]


viewBackgroundFields : Model -> String -> String -> TileBackground -> Html Msg
viewBackgroundFields model sectionId itemId background =
    let
        toMsg =
            SetLinkBackground sectionId itemId

        target slot =
            { sectionId = sectionId, itemId = itemId, slot = slot }

        kindButton kindLabel isKind newBackground =
            button
                [ type_ "button"
                , classList [ ( "editor-segment", True ), ( "editor-segment-active", isKind ) ]
                , attribute "aria-pressed"
                    (if isKind then
                        "true"

                     else
                        "false"
                    )
                , onClick
                    (if isKind then
                        toMsg background

                     else
                        toMsg newBackground
                    )
                ]
                [ text kindLabel ]

        ( isSolid, isImage, isVideo ) =
            case background of
                Solid _ ->
                    ( True, False, False )

                Image _ ->
                    ( False, True, False )

                Video _ ->
                    ( False, False, True )

        fields =
            case background of
                Solid color ->
                    [ label [ class "editor-field editor-color-field" ]
                        [ span [ class "editor-field-label" ] [ text "Color" ]
                        , input
                            [ type_ "color"
                            , class "editor-color"
                            , value color
                            , onInput (\c -> toMsg (Solid c))
                            ]
                            []
                        , span [ class "editor-color-value" ] [ text color ]
                        ]
                    ]

                Image url ->
                    [ mediaField model
                        (target ImageSrc)
                        { label = "Image URL"
                        , value = url
                        , placeholder = "https://"
                        , toMsg = \u -> toMsg (Image u)
                        }
                    ]

                Video clip ->
                    [ mediaField model
                        (target VideoSrc)
                        { label = "Video URL"
                        , value = clip.src
                        , placeholder = "https://….mp4"
                        , toMsg = \u -> toMsg (Video { clip | src = u })
                        }
                    , mediaField model
                        (target VideoPoster)
                        { label = "Poster image URL"
                        , value = clip.poster
                        , placeholder = "Shown before the video plays"
                        , toMsg = \u -> toMsg (Video { clip | poster = u })
                        }
                    ]
    in
    div [ class "editor-background" ]
        (div [ class "editor-field" ]
            [ span [ class "editor-field-label" ] [ text "Background" ]
            , div [ class "editor-segmented", attribute "role" "group", attribute "aria-label" "Background" ]
                [ kindButton "Color" isSolid (Solid defaultTileColor)
                , kindButton "Image" isImage (Image "")
                , kindButton "Video" isVideo (Video { src = "", poster = "" })
                ]
            ]
            :: fields
        )



-- VIEW HELPERS


textField :
    { label : String
    , value : String
    , placeholder : String
    , maxLength : Int
    , problem : Maybe String
    , toMsg : String -> Msg
    }
    -> Html Msg
textField config =
    label [ class "editor-field" ]
        [ span [ class "editor-field-label" ] [ text config.label ]
        , input
            [ type_ "text"
            , class "editor-input"
            , classList [ ( "editor-input-invalid", config.problem /= Nothing ) ]
            , value config.value
            , placeholder config.placeholder
            , maxlength config.maxLength
            , onInput config.toMsg
            ]
            []
        , case config.problem of
            Just problem ->
                span [ class "editor-field-problem" ] [ text problem ]

            Nothing ->
                text ""
        ]


{-| A URL field with an Upload button beside it. While uploading, the
field is locked and the button shows progress; a failed upload's message
replaces the URL problem until the next edit.
-}
mediaField :
    Model
    -> UploadTarget
    -> { label : String, value : String, placeholder : String, toMsg : String -> Msg }
    -> Html Msg
mediaField model target config =
    let
        state =
            uploadState model target

        uploading =
            case state of
                Just (Uploading percent) ->
                    Just percent

                _ ->
                    Nothing

        problem =
            case state of
                Just (UploadFailed message) ->
                    Just message

                Just (Uploading _) ->
                    Nothing

                Nothing ->
                    urlProblem config.value
    in
    div [ class "editor-field" ]
        [ div [ class "editor-media-row" ]
            [ label [ class "editor-media-label" ]
                [ span [ class "editor-field-label" ] [ text config.label ]
                , input
                    [ type_ "text"
                    , class "editor-input"
                    , classList [ ( "editor-input-invalid", problem /= Nothing ) ]
                    , value config.value
                    , placeholder config.placeholder
                    , maxlength 2000
                    , disabled (uploading /= Nothing)
                    , onInput config.toMsg
                    ]
                    []
                ]
            , button
                [ type_ "button"
                , class "editor-upload-button"
                , attribute "aria-label" (uploadLabel target.slot)
                , disabled (uploading /= Nothing)
                , onClick (RequestUpload target)
                ]
                (case uploading of
                    Just percent ->
                        [ text ("Uploading… " ++ String.fromInt percent ++ "%") ]

                    Nothing ->
                        [ i [ class "fa-solid fa-arrow-up-from-bracket", attribute "aria-hidden" "true" ] []
                        , text "Upload"
                        ]
                )
            ]
        , case problem of
            Just message ->
                span [ class "editor-field-problem" ] [ text message ]

            Nothing ->
                text ""
        ]


itemActions : String -> String -> String -> Int -> Int -> Html Msg
itemActions name sectionId itemId index count =
    div [ class "editor-row-actions" ]
        [ iconButton ("Move " ++ name ++ " up") "fa-arrow-up" (index > 0) (MoveItem sectionId itemId Up)
        , iconButton ("Move " ++ name ++ " down") "fa-arrow-down" (index < count - 1) (MoveItem sectionId itemId Down)
        , iconButton ("Remove " ++ name) "fa-trash-can" True (RemoveItem sectionId itemId)
        ]


iconButton : String -> String -> Bool -> Msg -> Html Msg
iconButton description icon enabled msg =
    button
        [ type_ "button"
        , class "editor-icon-button"
        , attribute "aria-label" description
        , title description
        , disabled (not enabled)
        , onClick msg
        ]
        [ i [ class ("fa-solid " ++ icon), attribute "aria-hidden" "true" ] [] ]


addButton : String -> Msg -> Html Msg
addButton description msg =
    button [ type_ "button", class "editor-add-button", onClick msg ]
        [ i [ class "fa-solid fa-plus", attribute "aria-hidden" "true" ] []
        , text description
        ]
