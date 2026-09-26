module Test.Generated.Main exposing (main)

import MainTest

import Test.Reporter.Reporter exposing (Report(..))
import Console.Text exposing (UseColor(..))
import Test.Runner.Node
import Test

main : Test.Runner.Node.TestProgram
main =
    Test.Runner.Node.run
        { runs = 100
        , report = ConsoleReport Monochrome
        , seed = 84790927429693
        , processes = 6
        , globs =
            []
        , paths =
            [ "/home/daniloss/dev/linktree/linktree/.claude/worktrees/page-editor/elm/tests/MainTest.elm"
            ]
        }
        [ ( "MainTest"
          , [ Test.Runner.Node.check MainTest.suite
            ]
          )
        ]