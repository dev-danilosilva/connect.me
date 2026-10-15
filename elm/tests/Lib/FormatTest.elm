module Lib.FormatTest exposing
    ( dateSuite
    , dateToMillisSuite
    , intSuite
    , monthDaySuite
    , monthSuite
    , weekdaySuite
    )

import Expect
import Fuzz
import Lib.Format as Format
import Test exposing (Test, describe, fuzz, test)
import Time


dayMillis : Float
dayMillis =
    86400000


intSuite : Test
intSuite =
    describe "Format.int"
        [ test "leaves numbers under a thousand alone" <|
            \_ -> Expect.equal [ "0", "7", "999" ] (List.map Format.int [ 0, 7, 999 ])
        , test "groups thousands with commas" <|
            \_ -> Expect.equal [ "1,000", "12,345", "1,234,567" ] (List.map Format.int [ 1000, 12345, 1234567 ])
        , test "keeps the minus sign out of the first group" <|
            \_ -> Expect.equal [ "-123", "-1,234", "-1,234,567" ] (List.map Format.int [ -123, -1234, -1234567 ])
        , fuzz Fuzz.int "only adds commas: removing them gives back String.fromInt" <|
            \n -> Expect.equal (String.fromInt n) (String.replace "," "" (Format.int n))
        , fuzz Fuzz.int "every group after the first has exactly three digits" <|
            \n ->
                Format.int n
                    |> String.split ","
                    |> List.drop 1
                    |> List.map String.length
                    |> List.all ((==) 3)
                    |> Expect.equal True
        ]


dateToMillisSuite : Test
dateToMillisSuite =
    describe "Format.dateToMillis"
        [ test "the Unix epoch is 0" <|
            \_ -> Expect.equal 0 (Format.dateToMillis "1970-01-01")
        , test "one day after the epoch" <|
            \_ -> Expect.equal dayMillis (Format.dateToMillis "1970-01-02")
        , test "dates before the epoch are negative" <|
            \_ -> Expect.equal -dayMillis (Format.dateToMillis "1969-12-31")
        , test "leap day" <|
            \_ -> Expect.equal 1709164800000 (Format.dateToMillis "2024-02-29")
        , test "the day after a 400-year leap February" <|
            \_ -> Expect.equal 951868800000 (Format.dateToMillis "2000-03-01")
        , test "malformed input is 0" <|
            \_ -> Expect.equal [ 0, 0, 0 ] (List.map Format.dateToMillis [ "", "2026-10", "not-a-date" ])
        , fuzz (Fuzz.intRange -50000 50000) "agrees with elm/time for any day (roughly 1833 to 2106)" <|
            \days ->
                let
                    millis =
                        toFloat days * dayMillis
                in
                Expect.equal millis (Format.dateToMillis (isoDate (Time.millisToPosix (round millis))))
        ]


dateSuite : Test
dateSuite =
    describe "Format.date"
        [ test "weekday, month and day" <|
            \_ -> Expect.equal "Thu, Oct 15" (Format.date "2026-10-15")
        , test "leap day" <|
            \_ -> Expect.equal "Thu, Feb 29" (Format.date "2024-02-29")
        , test "no zero padding on the day" <|
            \_ -> Expect.equal "Wed, Mar 1" (Format.date "2000-03-01")
        ]


monthDaySuite : Test
monthDaySuite =
    describe "Format.monthDay"
        [ test "the epoch is Jan 1" <|
            \_ -> Expect.equal "Jan 1" (Format.monthDay (Time.millisToPosix 0))
        , test "reads the date in UTC" <|
            \_ -> Expect.equal "Dec 31" (Format.monthDay (Time.millisToPosix -1))
        ]


monthSuite : Test
monthSuite =
    describe "Format.month"
        [ test "three-letter English names, in order" <|
            \_ ->
                List.map Format.month
                    [ Time.Jan, Time.Feb, Time.Mar, Time.Apr, Time.May, Time.Jun, Time.Jul, Time.Aug, Time.Sep, Time.Oct, Time.Nov, Time.Dec ]
                    |> Expect.equal [ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" ]
        ]


weekdaySuite : Test
weekdaySuite =
    describe "Format.weekday"
        [ test "three-letter English names, Monday first" <|
            \_ ->
                List.map Format.weekday [ Time.Mon, Time.Tue, Time.Wed, Time.Thu, Time.Fri, Time.Sat, Time.Sun ]
                    |> Expect.equal [ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" ]
        ]



-- HELPERS


{-| A UTC point in time -> "YYYY-MM-DD", built with elm/time only, so the
fuzz test checks `dateToMillis` against an independent calendar.
-}
isoDate : Time.Posix -> String
isoDate posix =
    String.join "-"
        [ String.fromInt (Time.toYear Time.utc posix)
        , String.padLeft 2 '0' (String.fromInt (monthNumber (Time.toMonth Time.utc posix)))
        , String.padLeft 2 '0' (String.fromInt (Time.toDay Time.utc posix))
        ]


monthNumber : Time.Month -> Int
monthNumber m =
    case m of
        Time.Jan ->
            1

        Time.Feb ->
            2

        Time.Mar ->
            3

        Time.Apr ->
            4

        Time.May ->
            5

        Time.Jun ->
            6

        Time.Jul ->
            7

        Time.Aug ->
            8

        Time.Sep ->
            9

        Time.Oct ->
            10

        Time.Nov ->
            11

        Time.Dec ->
            12
