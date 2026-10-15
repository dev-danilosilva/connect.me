module Lib.Format exposing
    ( date
    , dateToMillis
    , int
    , month
    , monthDay
    , weekday
    )

{-| Formatting helpers shared by the Elm programs: numbers, and the
"YYYY-MM-DD" dates Django sends in flags. All dates are treated as UTC.
Meant to be imported qualified: `Format.int 12345`, `Format.date "2026-10-15"`.
-}

import Time


{-| "2026-10-15" -> milliseconds since the Unix epoch, at UTC midnight.
-}
dateToMillis : String -> Float
dateToMillis isoDate =
    case List.map String.toInt (String.split "-" isoDate) of
        [ Just y, Just m, Just d ] ->
            toFloat (daysFromCivil y m d) * 86400000

        _ ->
            0


{-| Days since 1970-01-01 (Howard Hinnant's days_from_civil).
-}
daysFromCivil : Int -> Int -> Int -> Int
daysFromCivil y0 m d =
    let
        y =
            if m <= 2 then
                y0 - 1

            else
                y0

        era =
            y // 400

        yoe =
            y - era * 400

        mp =
            modBy 12 (m + 9)

        doy =
            (153 * mp + 2) // 5 + d - 1

        doe =
            yoe * 365 + yoe // 4 - yoe // 100 + doy
    in
    era * 146097 + doe - 719468


{-| "2026-10-15" -> "Thu, Oct 15"
-}
date : String -> String
date isoDate =
    let
        posix =
            Time.millisToPosix (round (dateToMillis isoDate))
    in
    weekday (Time.toWeekday Time.utc posix) ++ ", " ++ monthDay posix


{-| A point in time -> "Oct 15" (UTC)
-}
monthDay : Time.Posix -> String
monthDay posix =
    month (Time.toMonth Time.utc posix) ++ " " ++ String.fromInt (Time.toDay Time.utc posix)


{-| Time.Thu -> "Thu"
-}
weekday : Time.Weekday -> String
weekday day =
    case day of
        Time.Mon ->
            "Mon"

        Time.Tue ->
            "Tue"

        Time.Wed ->
            "Wed"

        Time.Thu ->
            "Thu"

        Time.Fri ->
            "Fri"

        Time.Sat ->
            "Sat"

        Time.Sun ->
            "Sun"


{-| Time.Oct -> "Oct"
-}
month : Time.Month -> String
month m =
    case m of
        Time.Jan ->
            "Jan"

        Time.Feb ->
            "Feb"

        Time.Mar ->
            "Mar"

        Time.Apr ->
            "Apr"

        Time.May ->
            "May"

        Time.Jun ->
            "Jun"

        Time.Jul ->
            "Jul"

        Time.Aug ->
            "Aug"

        Time.Sep ->
            "Sep"

        Time.Oct ->
            "Oct"

        Time.Nov ->
            "Nov"

        Time.Dec ->
            "Dec"


{-| 12345 -> "12,345", -1234 -> "-1,234"
-}
int : Int -> String
int n =
    let
        group digits =
            if String.length digits <= 3 then
                digits

            else
                group (String.dropRight 3 digits) ++ "," ++ String.right 3 digits
    in
    if n < 0 then
        "-" ++ group (String.fromInt (abs n))

    else
        group (String.fromInt n)
