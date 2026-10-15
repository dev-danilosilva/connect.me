module VisitsChart.Main exposing (main)

{-| The "Page visits" program: an interactive line chart of daily visits per
page, with a date-range filter and per-page toggles. Self-contained, so it can
be embedded anywhere that provides its flags; today that's the dashboard.

Started with `Elm.VisitsChart.Main.init`; compiled to static/js/visits_chart.js.

Flags: `{ "pages": [ { "handle", "title", "visits": [ { "date", "visits" } ] } ] }`,
currently mock data from the dashboard view (see `stats.mock_daily_visits`).
Every page's series is expected to cover the same days, oldest first.

-}

import Browser
import Browser.Dom as Dom
import Browser.Events
import Chart as C
import Chart.Attributes as CA
import Chart.Events as CE
import Chart.Item as CI
import Html exposing (Html, button, div, h2, p, span, strong, text)
import Html.Attributes exposing (attribute, class, classList, style, type_)
import Html.Events exposing (onClick)
import Json.Decode as Decode exposing (Decoder)
import Lib.Format as Format
import Lib.List
import Set exposing (Set)
import Task
import Time



-- MODEL


type alias PageVisits =
    { handle : String
    , title : String
    , visits : List DayVisits
    }


type alias DayVisits =
    { date : String
    , visits : Int
    }


{-| One line on the chart. `values` is aligned with `Model.days`.
-}
type alias Series =
    { key : String
    , name : String
    , color : String
    , values : List Float
    }


{-| One x position: a day, with every series' value at that index.
-}
type alias Datum =
    { x : Float
    , date : String
    , values : List Float
    }


type Range
    = Last7
    | Last30
    | Last90


type alias Model =
    { series : List Series
    , days : List Datum
    , range : Range
    , hidden : Set String
    , hovering : List (CI.Many Datum CI.Dot)
    , chartWidth : Float
    }


main : Program Decode.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


init : Decode.Value -> ( Model, Cmd Msg )
init flagsJson =
    let
        pages =
            Decode.decodeValue (Decode.field "pages" (Decode.list pageVisitsDecoder)) flagsJson
                |> Result.withDefault []

        series =
            toSeries pages
    in
    ( { series = series
      , days = toDays pages series
      , range = Last30
      , hidden = Set.empty
      , hovering = []
      , chartWidth = 900
      }
    , measureChart
    )


pageVisitsDecoder : Decoder PageVisits
pageVisitsDecoder =
    Decode.map3 PageVisits
        (Decode.field "handle" Decode.string)
        (Decode.field "title" Decode.string)
        (Decode.field "visits"
            (Decode.list
                (Decode.map2 DayVisits
                    (Decode.field "date" Decode.string)
                    (Decode.field "visits" Decode.int)
                )
            )
        )


{-| Categorical hues in fixed order; a page keeps its color no matter which
pages are toggled off. Past `palette`'s length the remaining pages fold into
a single "Other pages" line rather than reusing a hue.
-}
palette : List String
palette =
    [ "#9c2a9e", "#eb6834", "#1baf7a", "#2a78d6", "#eda100", "#008300", "#e87ba4", "#6250d6" ]


otherColor : String
otherColor =
    "#8a8288"


toSeries : List PageVisits -> List Series
toSeries pages =
    let
        values page =
            List.map (.visits >> toFloat) page.visits

        own color page =
            { key = page.handle, name = page.title, color = color, values = values page }
    in
    if List.length pages <= List.length palette then
        List.map2 own palette pages

    else
        let
            namedCount =
                List.length palette - 1

            rest =
                List.drop namedCount pages
        in
        List.map2 own palette (List.take namedCount pages)
            ++ [ { key = "__other__"
                 , name = "Other pages (" ++ String.fromInt (List.length rest) ++ ")"
                 , color = otherColor
                 , values = sumColumns (List.map values rest)
                 }
               ]


sumColumns : List (List Float) -> List Float
sumColumns rows =
    case rows of
        [] ->
            []

        first :: others ->
            List.foldl (List.map2 (+)) first others


toDays : List PageVisits -> List Series -> List Datum
toDays pages series =
    let
        dates =
            List.head pages |> Maybe.map (.visits >> List.map .date) |> Maybe.withDefault []

        seriesValueAt index s =
            Lib.List.at index s.values |> Maybe.withDefault 0
    in
    List.indexedMap
        (\index date ->
            { x = Format.dateToMillis date
            , date = date
            , values = List.map (seriesValueAt index) series
            }
        )
        dates



-- UPDATE


type Msg
    = SetRange Range
    | ToggleSeries String
    | OnHover (List (CI.Many Datum CI.Dot))
    | WindowResized
    | GotChartElement (Result Dom.Error Dom.Element)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SetRange range ->
            ( { model | range = range, hovering = [] }, Cmd.none )

        ToggleSeries key ->
            let
                hidden =
                    if Set.member key model.hidden then
                        Set.remove key model.hidden

                    else
                        Set.insert key model.hidden
            in
            ( { model | hidden = hidden, hovering = [] }, Cmd.none )

        OnHover hovering ->
            ( { model | hovering = hovering }, Cmd.none )

        WindowResized ->
            ( model, measureChart )

        GotChartElement (Ok { element }) ->
            ( { model | chartWidth = element.width, hovering = [] }, Cmd.none )

        GotChartElement (Err _) ->
            ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Browser.Events.onResize (\_ _ -> WindowResized)


{-| The chart is drawn at its container's real pixel width rather than scaled
from a fixed viewBox, so labels keep their size on narrow screens.
-}
measureChart : Cmd Msg
measureChart =
    Task.attempt GotChartElement (Dom.getElement chartId)


chartId : String
chartId =
    "visits-chart-plot"



-- VIEW


rangeDays : Range -> Int
rangeDays range =
    case range of
        Last7 ->
            7

        Last30 ->
            30

        Last90 ->
            90


rangeLabel : Range -> String
rangeLabel range =
    String.fromInt (rangeDays range) ++ "d"


visibleDays : Model -> List Datum
visibleDays model =
    List.drop (List.length model.days - rangeDays model.range) model.days


view : Model -> Html Msg
view model =
    Html.section [ class "visits-panel", attribute "aria-labelledby" "visits-title" ]
        [ div [ class "visits-panel-header" ]
            [ div []
                [ h2 [ class "visits-title", Html.Attributes.id "visits-title" ] [ text "Page visits" ]
                , viewTotal model
                ]
            , viewRangePicker model.range
            ]
        , if List.isEmpty model.series then
            p [ class "visits-empty" ] [ text "Create a page to start tracking its visits." ]

          else
            div []
                [ viewLegend model
                , div [ class "visits-chart", Html.Attributes.id chartId ] [ viewChart model ]
                , if isNarrow model then
                    viewReadout model

                  else
                    text ""
                ]
        ]


viewTotal : Model -> Html Msg
viewTotal model =
    let
        total =
            visibleDays model
                |> List.concatMap (\datum -> visibleValues model datum)
                |> List.sum
                |> round
    in
    p [ class "visits-total" ]
        [ strong [] [ text (Format.int total) ]
        , text (" visits in the last " ++ String.fromInt (rangeDays model.range) ++ " days")
        ]


visibleValues : Model -> Datum -> List Float
visibleValues model datum =
    List.map2 Tuple.pair model.series datum.values
        |> List.filter (\( s, _ ) -> not (Set.member s.key model.hidden))
        |> List.map Tuple.second


viewRangePicker : Range -> Html Msg
viewRangePicker current =
    div [ class "visits-range", attribute "role" "group", attribute "aria-label" "Date range" ]
        (List.map
            (\range ->
                button
                    [ type_ "button"
                    , classList [ ( "visits-range-btn", True ), ( "visits-range-btn-active", range == current ) ]
                    , attribute "aria-pressed" (boolString (range == current))
                    , onClick (SetRange range)
                    ]
                    [ text (rangeLabel range) ]
            )
            [ Last7, Last30, Last90 ]
        )


viewLegend : Model -> Html Msg
viewLegend model =
    div [ class "visits-legend" ]
        (List.map
            (\s ->
                let
                    shown =
                        not (Set.member s.key model.hidden)
                in
                button
                    [ type_ "button"
                    , classList [ ( "visits-legend-item", True ), ( "visits-legend-item-off", not shown ) ]
                    , attribute "aria-pressed" (boolString shown)
                    , onClick (ToggleSeries s.key)
                    ]
                    [ span [ class "visits-legend-swatch", style "background" s.color ] []
                    , text s.name
                    ]
            )
            model.series
        )


viewChart : Model -> Html Msg
viewChart model =
    let
        hoveredDots =
            List.concatMap CI.getMembers model.hovering

        line index s =
            if Set.member s.key model.hidden then
                Nothing

            else
                Just
                    (C.interpolated (valueAt index)
                        [ CA.monotone, CA.color s.color, CA.width 2 ]
                        [ CA.circle, CA.size 0, CA.color s.color ]
                        |> C.amongst hoveredDots
                            (\_ -> [ CA.size 40, CA.border "#ffffff", CA.borderWidth 2 ])
                        |> C.named s.name
                    )
    in
    C.chart
        [ CA.height
            (if isNarrow model then
                220

             else
                280
            )
        , CA.width model.chartWidth
        , CA.margin { top = 12, bottom = 28, left = 44, right = 16 }
        , CE.onMouseMove OnHover (CE.getNearestX (CI.andThen CI.sameX CI.dots))
        , CE.onMouseLeave (OnHover [])
        ]
        [ C.yLabels [ CA.withGrid, CA.ints, CA.amount 4, CA.color "#7a5c80", CA.fontSize 12 ]
        , C.xLabels [ CA.times Time.utc, CA.format formatTick, CA.amount (max 3 (round (model.chartWidth / 150))), CA.color "#7a5c80", CA.fontSize 12 ]
        , C.xAxis [ CA.noArrow, CA.color "#d9c3e0" ]
        , C.series .x (List.filterMap identity (List.indexedMap line model.series)) (visibleDays model)
        , C.each model.hovering <|
            \_ item ->
                let
                    x =
                        CI.getX (CI.getMember item)
                in
                [ C.line [ CA.x1 x, CA.x2 x, CA.color "#b9a4bf", CA.width 1, CA.dashed [ 4, 4 ] ]
                , if isNarrow model then
                    C.none

                  else
                    C.tooltip item [ CA.onLeftOrRight, CA.offset 14 ] [] [ viewTooltip item ]
                ]
        ]


{-| Too narrow for a tooltip beside the cursor: hovered values show in a
readout under the chart instead (see `viewReadout`).
-}
isNarrow : Model -> Bool
isNarrow model =
    model.chartWidth < 520


{-| The hovered day, or the latest one when nothing is hovered, so the
readout keeps its height and the layout doesn't jump on touch.
-}
viewReadout : Model -> Html Msg
viewReadout model =
    let
        day =
            case List.head model.hovering of
                Just item ->
                    Just (CI.getOneData item)

                Nothing ->
                    List.head (List.reverse model.days)

        shownSeries =
            List.filter (\s -> not (Set.member s.key model.hidden)) model.series
    in
    case day of
        Nothing ->
            text ""

        Just datum ->
            div [ class "visits-readout" ]
                [ Html.map never
                    (viewDayValues datum.date
                        (List.map
                            (\( s, value ) -> { name = s.name, color = s.color, value = value })
                            (List.filter (\( s, _ ) -> List.member s shownSeries)
                                (List.map2 Tuple.pair model.series datum.values)
                            )
                        )
                    )
                ]


valueAt : Int -> Datum -> Float
valueAt index datum =
    Lib.List.at index datum.values |> Maybe.withDefault 0


viewTooltip : CI.Many Datum CI.Dot -> Html Never
viewTooltip item =
    viewDayValues (CI.getOneData item).date
        (List.map
            (\dot -> { name = CI.getName dot, color = CI.getColor dot, value = CI.getY dot })
            (CI.getMembers item)
        )


viewDayValues : String -> List { name : String, color : String, value : Float } -> Html Never
viewDayValues date rows =
    let
        row r =
            div [ class "visits-tooltip-row" ]
                [ span [ class "visits-legend-swatch", style "background" r.color ] []
                , span [ class "visits-tooltip-name" ] [ text r.name ]
                , strong [] [ text (Format.int (round r.value)) ]
                ]

        totalRow =
            if List.length rows > 1 then
                [ div [ class "visits-tooltip-row visits-tooltip-total" ]
                    [ span [ class "visits-tooltip-name" ] [ text "Total" ]
                    , strong [] [ text (Format.int (round (List.sum (List.map .value rows)))) ]
                    ]
                ]

            else
                []
    in
    div [ class "visits-tooltip" ]
        (div [ class "visits-tooltip-date" ] [ text (Format.date date) ]
            :: List.map row rows
            ++ totalRow
        )



-- HELPERS


boolString : Bool -> String
boolString b =
    if b then
        "true"

    else
        "false"


{-| An x-axis tick (UTC millis) -> "Oct 15"
-}
formatTick : Float -> String
formatTick millis =
    Format.monthDay (Time.millisToPosix (round millis))
