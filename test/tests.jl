"""
Test testing utils, used in the rest of the test suite.
They should generate useful, contextualized reports.
"""
module TestTests

using EcologicalNetworksDynamics: Tests, ErrWith
using .Tests: @fails, @test_err
using Test

const TT = TestTests

# Example expected exception to be caught and verified.
struct ExpectedException <: Exception
    field::Integer
    mess::String
end

# Test that errors report the correct failure file (this one),
# and at the correct location.
"Expand to invocation site `file:line` with the given offset applied."
macro HERE(shift = 0)
    (; file, line) = __source__
    file = QuoteNode(file)
    line += shift
    quote
        "$($file):$($line)"
    end
end

@testset "@fails macro" begin
    let # Wrap in hard scope to verify macro hygiene.
        Expected = ExpectedException # The *local* name is used within invocations.

        "Raise the error to be tested."
        f() = throw(Expected(5, "err"))
        f_line = @HERE -1

        "Use to check that stack frames point here as an unexpected error origin."
        invalid() = INVALID
        invalid_line = @HERE -1

        # Successful invocation: the tested function fails as expected.
        @fails f() Expected 5 "err"

        #-----------------------------------------------------------------------------------
        # Cannot evaluate error type, rest of input still unevaluated.
        @test_err(
            () -> (@fails x INVALID x),
            """
            When evaluating expected error type:
            @@@ $(@HERE -3) @@@
              INVALID
            UndefVarError: `INVALID` not defined in `$TT`
            Suggestion: check for spelling errors or missing imports.\
            """,
            #  (@HERE -8), # Would be nice :')
            # TODO: the frame cannot always be tested because
            # we got few control over it yet. Fix when that changes, or hack around.
            # https://julialang.zulipchat.com/#narrow/channel/274208-helpdesk-.28published.29/topic/Trim.20exposed.20stracktraces.2E/with/613806373
        )

        #-----------------------------------------------------------------------------------
        # Cannot evaluate error type. Pointing to the right user-code error.

        @test_err(
            () -> (@fails x invalid() x),
            """
            When evaluating expected error type:
            @@@ $(@HERE -3) @@@
              invalid()
            UndefVarError: `INVALID` not defined in `$TT`
            Suggestion: check for spelling errors or missing imports.\
            """,
            invalid_line,
        )

        #-----------------------------------------------------------------------------------
        # Not an error type.

        @test_err(
            () -> (@fails x :INVALID x),
            """
            Not an exception type:
            @@@ $(@HERE -3) @@@
              :INVALID  ::Symbol\
            """,
            nothing,# Too bad :')
        )

        #-----------------------------------------------------------------------------------
        # Wrong number of fields tested. Expression still unevaluated.

        @test_err(
            () -> (@fails x Expected x), # Evaluation successful within the `let` block.
            """
            Wrong number of error fields:
            @@@ $(@HERE -3) @@@
            This error type requires checking 2 fields:
              $Expected(:field, :mess)
            but input contains 1 value to be checked against:
              - :x\
            """,
            nothing,
        )

        #-----------------------------------------------------------------------------------
        # Fields evaluation error.

        @test_err(
            () -> (@fails x Expected 5 INVALID),
            """
            When evaluating expected error fields:
            @@@ $(@HERE -3) @@@
              (5, :INVALID)
            UndefVarError: `INVALID` not defined in `$TT`
            Suggestion: check for spelling errors or missing imports.\
            """,
            nothing,
        )

        @test_err(
            () -> (@fails x Expected 5 invalid()),
            """
            When evaluating expected error fields:
            @@@ $(@HERE -3) @@@
              (5, :(invalid()))
            UndefVarError: `INVALID` not defined in `$TT`
            Suggestion: check for spelling errors or missing imports.\
            """,
            invalid_line, # <- That's the difference.
        )

        #-----------------------------------------------------------------------------------
        # No actual error collected (fields values unchecked).

        @test_err(
            () -> (@fails (5 + 8) Expected -1 -1),
            """
            Unexpected success:
            @@@ $(@HERE -3) @@@
               -------------------expected----------------
            $Expected(-1, -1)
               --------------------actual-----------------
            <no actual error obtained>
            """,
            nothing,
        )

        #-----------------------------------------------------------------------------------
        # Unexpected error obtained (fields values unchecked).

        @test_err(
            () -> (@fails (5 + :a) Expected -1 -1),
            """
            Unexpected error type:
            @@@ $(@HERE -3) @@@
               -------------------expected----------------
            $Expected(-1, -1)
               --------------------actual-----------------
            MethodError: no method matching +(::Int64, ::Symbol)
            The function `+` exists, but no method is defined \
             for this combination of argument types.

            Closest candidates are:
              +(::Any, ::Any, !Matched::Any, !Matched::Any...)
               @ Base operators.jl:642
              +(::Real, !Matched::Complex{Bool})
               @ Base complex.jl:322
              +(::Real, !Matched::Complex)
               @ Base complex.jl:334
              ...
            """,
            nothing,
        )

        #-----------------------------------------------------------------------------------
        # Unexpected (generic) error field value.

        @test_err(
            () -> (@fails f() Expected -1 "err"),
            """
            Unexpected field :field value:
            @@@ $(@HERE -3) @@@
            in $Expected:
               -------------------expected----------------
              -1  ::$Int
               --------------------actual-----------------
              5  ::$Int
            """,
            f_line,
        )

        #-----------------------------------------------------------------------------------
        # Unexpected error message field.

        @test_err(
            () -> (@fails f() Expected 5 "invalid"),
            """
            Unexpected error message:
            @@@ $(@HERE -3) @@@
            in $Expected:
            The two error message fields differ:
            expected: invalid
              actual: err
            """,
            f_line,
        )

    end
end

end
