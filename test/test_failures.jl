module TestFailures

# @test_throws cannot check failures *during macro expansion* :\
# So mimick it with this macro that first expands it within a try block.
# (also, I find it better to be able to check both the error type *and* its content/message)
#
# Inconvenience: custom error checkers can be defined, but their pattern arguments
# need to be dynamically `eval`uated since their are passed to macro calls.
# As a consequence, there needs two kinds of "@expect_failure" macros:
# one expecting failure *during expansion*, evaluating their arguments at expansion time,
# and one expecting failure *during execution*, only evaluating arguments during execution.
#
# The "exception pattern" argument is used to match the expected exception.
# It is typically of the form `ExceptionType` or `ExceptionType => (args...,)`,
# with a user-defined specification, once the exception has been typechecked,
# what to check with the given arguments.

using Test
using Crayons

# Default exposed macro,
# build your own  from `failswith()` function, doing most of the job.
macro failswith(expression, pattern, kw = :execution)
    expect_expansion_failure = if kw in (:xc, :exec, :execution)
        false
    elseif kw in (:xp, :exp, :expand, :expansion)
        true
    else
        throw(ArgumentError("Invalid keyword in @failswith macro call.\
                             Expected :expansion or :execution, got: $(repr(kw))."))
    end
    failswith(__source__, __module__, expression, pattern, expect_expansion_failure)
end
export @failswith

function failswith(src, mod, xp, exception_pattern, expect_expansion_failure)
    (; file, line) = src
    loc = "$(crayon"blue")$file:$line$(crayon"reset")"
    if expect_expansion_failure
        # Evaluate the exception pattern
        # in the invocation context, at expansion time.
        exception_pattern = Core.eval(mod, exception_pattern)
    end
    # Check expansion separately.
    code = try
        Core.eval(mod, :(@macroexpand $xp))
    catch e
        # An unexpected error will trigger another exception.
        # Since this happens during macro expansion,
        # catch it before it bubbles up to the tests dev
        # to highlight useful file/line information where it happened.
        if expect_expansion_failure
            try
                _check_exception(exception_pattern, e)
            catch e
                @error "Macro expansion did not fail as expected: $loc"
                rethrow(e)
            else
                # Otherwise the macro failed as expected.
                return :($Test.@test true) # Count as one for the surrounding @testset.
            end
        else
            @error "Macro unexpectedly failed during expansion: $loc"
            rethrow(e)
        end
    end
    # Expansion succeeded.
    if expect_expansion_failure
        error("Unexpected macro expansion success at $loc\n\
               Was expecting: $exception_pattern.")
    end
    # Test actual generated code.
    @gensym e # Otherwise unhygienic.
    esc(quote
        try
            $code
        catch $e
            try
                # Evaluate the exception pattern
                # in the invocation context, at execution time.
                $_check_exception($exception_pattern, $e)
                $Test.@test true # Count as one for the surrounding @testset.
            catch $e
                @error $"The tested code did not fail as expected: $loc"
                rethrow($e)
            end
        else
            $error($"Unexpected success at $loc\nWas expecting: $exception_pattern", throw)
        end
    end)
end

function _check_exception(exception_pattern, e)
    # Assume that a possible wrapping LoadError is undesired.
    e isa LoadError && (e = e.error)
    _check_unwrapped_exception(exception_pattern, e)
end

# Common exception checker: only the type (like @test_throws).
function _check_unwrapped_exception(ExceptionType::Type, e)
    e isa ExceptionType || error("Expected error type:\n  $ExceptionType\n\
                                  got instead:\n  $(typeof(e))")
end

# Common exception checker: the actual exception value field by field (like @test_throws).
function _check_unwrapped_exception(expected::Exception, actual)
    E = typeof(expected)
    _check_unwrapped_exception(E, actual)
    for field in fieldnames(E)
        getfield(expected, field) == getfield(actual, field) ||
            error("Expected error:\n  $expected\ngot instead:\n  $actual")
    end
end

# To check more than the type, provide args under the form ExceptionType => (args,..)
# and implementation for what they mean to the type.
function _check_unwrapped_exception(pair::Pair, e)
    ExceptionType, args = pair
    _check_unwrapped_exception(ExceptionType, e) # Type is checked anyway.
    check_exception(e, args...)
end

# If anything else than an exception is thrown, just test for equality.
function _check_unwrapped_exception(thrown, actual)
    thrown == actual ||
        error("Expected thrown value:\n  $(repr(thrown)) ::$(typeof(thrown))\n\
               got instead:\n  $(repr(actual)) ::$(typeof(actual))")
end

# Open end for user extension.
function check_exception(e::Exception, args...)
    error("Unimplemented exception checking:\n  $(typeof(e)) => $args ::$(typeof(args))\n\
           Received exception $e.")
end

#-------------------------------------------------------------------------------------------
# Module-dedicated error.
struct FailedFailure <: Exception
    message::String
end
Base.showerror(io::IO, e::FailedFailure) = print(io, "Failed failure test: $(e.message)")
# Local override.
error(mess, throw = rethrow) = throw(FailedFailure(mess))

#-------------------------------------------------------------------------------------------
# Convenience message checking utils.

function check_message(exact::String, m)
    (exact == m) || error("Expected vs. actual error messages:\n\
                           --------------------------------------\n\
                           >>> $exact\n\
                           <<< $m\n\
                           -------------------------------------")
end

function check_message(substrings::Vector{String}, m)
    # Seek substrings.
    for needle in substrings
        occursin(needle, m) || error("Expected to find substring:\n  $needle\n\
                                      in error message, but got:\n  $m")
    end
end

function check_message(pattern::Regex, m)
    isnothing(match(pattern, m)) && error("Error message was supposed to match:\n $needle\n\
                                           but it does not:\n   $m")
end

#-------------------------------------------------------------------------------------------
# Common expected errors.

# ArgumentError.
function check_exception(e::ArgumentError, message_pattern)
    TestFailures.check_message(message_pattern, eval(e.msg))
end
# Expect failure during expansion.
macro xargfails(xp, mess)
    TestFailures.failswith(__source__, __module__, xp, :(ArgumentError => ($mess,)), true)
end
# Expect failure during execution.
macro argfails(xp, mess)
    TestFailures.failswith(__source__, __module__, xp, :(ArgumentError => ($mess,)), false)
end
export @xargfails, @argfails

# UndefVarError.
function check_exception(e::UndefVarError, var, scope)
    e.var == var ||
        error("Expected undefined symbol: $(repr(var)), got instead: $(repr(e.var))")
    # This appeared and broke the tests.
    if VERSION >= v"1.11"
        e.scope === scope ||
            error("Expected undefined scope: $(repr(scope)), got instead: $(repr(e.scope))")
    end
end

end
