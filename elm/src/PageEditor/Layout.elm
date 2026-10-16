module PageEditor.Layout exposing
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
    , decoder
    , encode
    , networkIcon
    , networkLabel
    )

{-| A page's layout, spec version 1 (docs/page-layout-spec-v1.md).

An ordered list of typed sections; a links section holds an ordered list of
typed tiles. A new kind of section or tile is a new constructor in
`SectionContent` or `TileContent`, plus its decoder and encoder branches here
and its view in PageEditor.Preview.

Django validates every document it stores (personal\_links\_manager/layout),
so the decoder only needs to read what the spec allows.

-}

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


version : Int
version =
    1


type alias Layout =
    { sections : List Section
    }


type alias Section =
    { id : String
    , content : SectionContent
    }


type SectionContent
    = Hero HeroData
    | Socials (List Social)
    | Links (List Tile)


type alias HeroData =
    { displayName : String
    , bio : String

    -- Empty when the page has no hero image.
    , imageUrl : String
    }


type alias Social =
    { id : String
    , network : Network
    , url : String
    }


type Network
    = Instagram
    | YouTube
    | GitHub
    | LinkedIn
    | X
    | TikTok
    | Facebook
    | Spotify
    | Website


type alias Tile =
    { id : String
    , content : TileContent
    }


type TileContent
    = LinkTile Link


type alias Link =
    { label : String
    , url : String
    , background : TileBackground
    }


{-| What fills a link tile behind its label: a #rrggbb color, or an image
or video URL.
-}
type TileBackground
    = Solid String
    | Image String
    | Video { src : String, poster : String }



-- NETWORKS


allNetworks : List Network
allNetworks =
    [ Instagram, YouTube, GitHub, LinkedIn, X, TikTok, Facebook, Spotify, Website ]


{-| The network's name in the spec, Font Awesome icon classes and label.
-}
networkInfo : Network -> { name : String, icon : String, label : String }
networkInfo network =
    case network of
        Instagram ->
            { name = "instagram", icon = "fa-brands fa-instagram", label = "Instagram" }

        YouTube ->
            { name = "youtube", icon = "fa-brands fa-youtube", label = "YouTube" }

        GitHub ->
            { name = "github", icon = "fa-brands fa-github", label = "GitHub" }

        LinkedIn ->
            { name = "linkedin", icon = "fa-brands fa-linkedin", label = "LinkedIn" }

        X ->
            { name = "x", icon = "fa-brands fa-x-twitter", label = "X" }

        TikTok ->
            { name = "tiktok", icon = "fa-brands fa-tiktok", label = "TikTok" }

        Facebook ->
            { name = "facebook", icon = "fa-brands fa-facebook", label = "Facebook" }

        Spotify ->
            { name = "spotify", icon = "fa-brands fa-spotify", label = "Spotify" }

        Website ->
            { name = "website", icon = "fa-solid fa-globe", label = "Website" }


{-| Font Awesome classes for the network's icon, e.g. "fa-brands fa-github".
-}
networkIcon : Network -> String
networkIcon network =
    (networkInfo network).icon


networkLabel : Network -> String
networkLabel network =
    (networkInfo network).label



-- DECODING


decoder : Decoder Layout
decoder =
    Decode.field "version" Decode.int
        |> Decode.andThen
            (\v ->
                if v == version then
                    Decode.map Layout (Decode.field "sections" (Decode.list sectionDecoder))

                else
                    Decode.fail ("Unsupported layout version " ++ String.fromInt v)
            )


{-| Decodes `type` first, then the fields of that type.
-}
typed : (String -> Decoder a) -> Decoder a
typed byType =
    Decode.field "type" Decode.string |> Decode.andThen byType


sectionDecoder : Decoder Section
sectionDecoder =
    Decode.map2 Section
        (Decode.field "id" Decode.string)
        (typed sectionContentDecoder)


sectionContentDecoder : String -> Decoder SectionContent
sectionContentDecoder kind =
    case kind of
        "hero" ->
            Decode.map Hero
                (Decode.map3 HeroData
                    (Decode.field "displayName" Decode.string)
                    (Decode.field "bio" Decode.string)
                    (Decode.field "imageUrl" Decode.string)
                )

        "socials" ->
            Decode.map Socials (Decode.field "items" (Decode.list socialDecoder))

        "links" ->
            Decode.map Links (Decode.field "items" (Decode.list tileDecoder))

        _ ->
            Decode.fail ("Unknown section type " ++ kind)


socialDecoder : Decoder Social
socialDecoder =
    Decode.map3 Social
        (Decode.field "id" Decode.string)
        (Decode.field "network" networkDecoder)
        (Decode.field "url" Decode.string)


networkDecoder : Decoder Network
networkDecoder =
    Decode.string
        |> Decode.andThen
            (\name ->
                case List.filter (\network -> (networkInfo network).name == name) allNetworks of
                    network :: _ ->
                        Decode.succeed network

                    [] ->
                        Decode.fail ("Unknown network " ++ name)
            )


tileDecoder : Decoder Tile
tileDecoder =
    Decode.map2 Tile
        (Decode.field "id" Decode.string)
        (typed tileContentDecoder)


tileContentDecoder : String -> Decoder TileContent
tileContentDecoder kind =
    case kind of
        "link" ->
            Decode.map LinkTile
                (Decode.map3 Link
                    (Decode.field "label" Decode.string)
                    (Decode.field "url" Decode.string)
                    (Decode.field "background" (typed backgroundDecoder))
                )

        _ ->
            Decode.fail ("Unknown tile type " ++ kind)


backgroundDecoder : String -> Decoder TileBackground
backgroundDecoder kind =
    case kind of
        "solid" ->
            Decode.map Solid (Decode.field "color" Decode.string)

        "image" ->
            Decode.map Image (Decode.field "url" Decode.string)

        "video" ->
            Decode.map2 (\src poster -> Video { src = src, poster = poster })
                (Decode.field "src" Decode.string)
                (Decode.field "poster" Decode.string)

        _ ->
            Decode.fail ("Unknown tile background " ++ kind)



-- ENCODING


encode : Layout -> Encode.Value
encode layout =
    Encode.object
        [ ( "version", Encode.int version )
        , ( "sections", Encode.list encodeSection layout.sections )
        ]


withType : String -> String -> List ( String, Encode.Value ) -> Encode.Value
withType id kind fields =
    Encode.object (( "id", Encode.string id ) :: ( "type", Encode.string kind ) :: fields)


encodeSection : Section -> Encode.Value
encodeSection section =
    case section.content of
        Hero hero ->
            withType section.id
                "hero"
                [ ( "displayName", Encode.string hero.displayName )
                , ( "bio", Encode.string hero.bio )
                , ( "imageUrl", Encode.string hero.imageUrl )
                ]

        Socials socials ->
            withType section.id "socials" [ ( "items", Encode.list encodeSocial socials ) ]

        Links tiles ->
            withType section.id "links" [ ( "items", Encode.list encodeTile tiles ) ]


encodeSocial : Social -> Encode.Value
encodeSocial social =
    Encode.object
        [ ( "id", Encode.string social.id )
        , ( "network", Encode.string (networkInfo social.network).name )
        , ( "url", Encode.string social.url )
        ]


encodeTile : Tile -> Encode.Value
encodeTile tile =
    case tile.content of
        LinkTile link ->
            withType tile.id
                "link"
                [ ( "label", Encode.string link.label )
                , ( "url", Encode.string link.url )
                , ( "background", encodeBackground link.background )
                ]


encodeBackground : TileBackground -> Encode.Value
encodeBackground background =
    case background of
        Solid color ->
            Encode.object [ ( "type", Encode.string "solid" ), ( "color", Encode.string color ) ]

        Image url ->
            Encode.object [ ( "type", Encode.string "image" ), ( "url", Encode.string url ) ]

        Video clip ->
            Encode.object
                [ ( "type", Encode.string "video" )
                , ( "src", Encode.string clip.src )
                , ( "poster", Encode.string clip.poster )
                ]
