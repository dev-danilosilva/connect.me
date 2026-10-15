module PageEditor.PagePreview exposing
    ( Link
    , LinkPage
    , SocialLink
    , TileBackground(..)
    , dummy
    , view
    )

{-| The public link page as visitors see it, rendered in the editor's preview.

Markup only: every class is `lp-` prefixed and styled by
static/css/link_page.css, scoped under the `.lp-page` root. Nothing in here
should depend on the editor's CSS.

-}

import Html exposing (Html, a, div, footer, h1, header, i, img, li, p, span, text, ul, video)
import Html.Attributes exposing (alt, attribute, autoplay, class, href, loop, poster, property, rel, src, style, target)
import Json.Encode


type alias LinkPage =
    { displayName : String
    , bio : String
    , heroImageUrl : String
    , socials : List SocialLink
    , links : List Link
    }


type alias SocialLink =
    { label : String
    , icon : String
    , url : String
    }


type alias Link =
    { label : String
    , url : String
    , background : TileBackground
    }


{-| What fills a link tile behind its label. Colors and gradients are CSS
values; images and videos are URLs.
-}
type TileBackground
    = Solid String
    | Gradient String
    | Image String
    | Video { src : String, poster : String }


{-| Hardcoded placeholder content until the editor loads real page data.
-}
dummy : LinkPage
dummy =
    { displayName = "Ada Lovelace"
    , bio = "Mathematician · writing about the Analytical Engine and the poetry of numbers."
    , heroImageUrl = "https://picsum.photos/seed/lovelace/1200/900"
    , socials =
        [ { label = "Instagram", icon = "fa-instagram", url = "https://instagram.com/" }
        , { label = "YouTube", icon = "fa-youtube", url = "https://youtube.com/" }
        , { label = "GitHub", icon = "fa-github", url = "https://github.com/" }
        , { label = "LinkedIn", icon = "fa-linkedin", url = "https://linkedin.com/" }
        ]
    , links =
        [ { label = "Watch my talk"
          , url = "https://example.com/talk"
          , background =
                Video
                    { src = "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4"
                    , poster = "https://picsum.photos/seed/lovelace-talk/600/600"
                    }
          }
        , { label = "Read my latest essay"
          , url = "https://example.com/essay"
          , background = Image "https://picsum.photos/seed/lovelace-essay/600/600"
          }
        , { label = "Notes on the Analytical Engine"
          , url = "https://example.com/notes"
          , background = Gradient "linear-gradient(135deg, #7c3aed 0%, #db2777 100%)"
          }
        , { label = "Book a call"
          , url = "https://example.com/call"
          , background = Solid "#4c1d95"
          }
        , { label = "Gallery"
          , url = "https://example.com/gallery"
          , background = Image "https://picsum.photos/seed/lovelace-gallery/600/600"
          }
        , { label = "Newsletter"
          , url = "https://example.com/newsletter"
          , background = Solid "#0f766e"
          }
        ]
    }


view : LinkPage -> Html msg
view page =
    div [ class "lp-page" ]
        [ viewHero page
        , div [ class "lp-content" ]
            [ ul [ class "lp-socials" ] (List.map viewSocial page.socials)
            , ul [ class "lp-links" ] (List.map viewLink page.links)
            , footer [ class "lp-footer" ] [ text "mylinks.app" ]
            ]
        ]


viewHero : LinkPage -> Html msg
viewHero page =
    header [ class "lp-hero" ]
        [ -- Decorative: the name and bio over it carry the meaning.
          img [ class "lp-hero-image", src page.heroImageUrl, alt "" ] []
        , div [ class "lp-hero-text" ]
            [ h1 [ class "lp-name" ] [ text page.displayName ]
            , p [ class "lp-bio" ] [ text page.bio ]
            ]
        ]


viewSocial : SocialLink -> Html msg
viewSocial social =
    li []
        [ a
            [ class "lp-social"
            , href social.url
            , target "_blank"
            , rel "noopener noreferrer"
            , attribute "aria-label" social.label
            ]
            [ i [ class ("fa-brands " ++ social.icon), attribute "aria-hidden" "true" ] [] ]
        ]


viewLink : Link -> Html msg
viewLink link =
    let
        ( kind, backgroundAttrs, media ) =
            case link.background of
                Solid color ->
                    ( "solid", [ style "background" color ], [] )

                Gradient gradient ->
                    ( "gradient", [ style "background" gradient ], [] )

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

