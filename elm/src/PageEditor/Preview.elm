module PageEditor.Preview exposing (view)

{-| The public link page as visitors see it, rendered in the editor's preview
from the page's layout.

Markup only: every class is `lp-` prefixed and styled by
static/css/link\_page.css, scoped under the `.lp-page` root. Nothing in here
should depend on the editor's CSS.

-}

import Html exposing (Html, a, div, footer, h1, header, i, img, li, p, section, span, text, ul, video)
import Html.Attributes exposing (alt, attribute, autoplay, class, href, loop, poster, property, rel, src, style, target)
import Json.Encode
import PageEditor.Layout as Layout exposing (HeroData, Layout, Link, Section, SectionContent(..), Social, Tile, TileBackground(..), TileContent(..))


{-| Sections render in the layout's order, then the footer.
-}
view : Layout -> Html msg
view layout =
    div [ class "lp-page" ]
        (List.map viewSection layout.sections
            ++ [ footer [ class "lp-footer" ] [ text "mylinks.app" ] ]
        )


viewSection : Section -> Html msg
viewSection { content } =
    case content of
        Hero hero ->
            viewHero hero

        Socials socials ->
            section [ class "lp-section lp-section--socials" ]
                [ ul [ class "lp-socials" ] (List.map viewSocial socials) ]

        Links tiles ->
            section [ class "lp-section lp-section--links" ]
                [ ul [ class "lp-links" ] (List.map viewTile tiles) ]


{-| Without an image, the hero shows its fallback background.
-}
viewHero : HeroData -> Html msg
viewHero hero =
    header [ class "lp-hero" ]
        ((if String.isEmpty hero.imageUrl then
            []

          else
            -- Decorative: the name and bio over it carry the meaning.
            [ img [ class "lp-hero-image", src hero.imageUrl, alt "" ] [] ]
         )
            ++ [ div [ class "lp-hero-text" ]
                    [ h1 [ class "lp-name" ] [ text hero.displayName ]
                    , p [ class "lp-bio" ] [ text hero.bio ]
                    ]
               ]
        )


viewSocial : Social -> Html msg
viewSocial social =
    li []
        [ a
            [ class "lp-social"
            , href social.url
            , target "_blank"
            , rel "noopener noreferrer"
            , attribute "aria-label" (Layout.networkLabel social.network)
            ]
            [ i [ class (Layout.networkIcon social.network), attribute "aria-hidden" "true" ] [] ]
        ]


viewTile : Tile -> Html msg
viewTile tile =
    case tile.content of
        LinkTile link ->
            viewLink link


viewLink : Link -> Html msg
viewLink link =
    let
        ( kind, backgroundAttrs, media ) =
            case link.background of
                Solid color ->
                    ( "solid", [ style "background" color ], [] )

                Image url ->
                    -- Decorative: the label carries the meaning.
                    ( "image", [], [ img [ class "lp-tile-media", src url, alt "" ] [] ] )

                Video clip ->
                    -- The poster also paints the tile, so it still shows
                    -- when the stylesheet hides the video (reduced motion).
                    ( "video"
                    , [ style "background" ("center / cover no-repeat url(\"" ++ clip.poster ++ "\")") ]
                    , [ viewTileVideo clip ]
                    )
    in
    li []
        [ a
            ([ class ("lp-tile lp-tile--" ++ kind)
             , href link.url
             , target "_blank"
             , rel "noopener noreferrer"
             ]
                ++ backgroundAttrs
            )
            (media ++ [ span [ class "lp-tile-label" ] [ text link.label ] ])
        ]


{-| Phones only autoplay muted video. The `muted` attribute only sets the
muted state when the parser creates the element, so Elm also sets the
property.
-}
viewTileVideo : { src : String, poster : String } -> Html msg
viewTileVideo clip =
    video
        [ class "lp-tile-media"
        , src clip.src
        , poster clip.poster
        , autoplay True
        , loop True
        , attribute "muted" ""
        , property "muted" (Json.Encode.bool True)
        , attribute "playsinline" ""
        , attribute "aria-hidden" "true"
        ]
        []

