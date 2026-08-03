"""
Various testing utils related to compare strings displayed in console,
useful for testing the "snapshot" style
with a hepful summary displayed in case of mismatch.
Functions prefixed with `test_*` in this are preferred for use outside `@testset` blocks,
whereas corresponding `@test_*` macros are prefererd for use inside `@testset` blocks.
Either will record +1 success in testing statistics in case of success,
but the former will error in case of failure
while the latter will just count as +1 failure
and correctly point to the right failed test location.
"""
module Strings

using EcologicalNetworksDynamics: Display, Option, errwith
using .Display: yellow, blue, red, bold, reset, wide_repr

using Test
using StringManipulation: remove_decorations

const S = Strings

"""
The error raised in case of strings mismatch,
supposed to display a hepful comparison report.
"""
struct UnmatchedStrings <: Exception
    what::String
    expected::String
    actual::String
end

function Base.showerror(io::IO, e::UnmatchedStrings)
    (; what, expected, actual) = e
    println(io, "$(yellow)The two $what differ:$reset")
    if !('\n' in actual || '\n' in expected)
        # Single-line display.
        println(io, "$(blue)expected:$reset $expected")
        println(io, "$(red)  actual:$reset $actual")
    else
        spread_compare(io, expected, actual)
        a_it, e_it = eachsplit.((actual, expected), '\n')
        a_next = iterate(a_it)
        e_next = iterate(e_it)
        while true
            isnothing(a_next) && isnothing(e_next) &&
                throw("Should be different, right?")
            if isnothing(a_next)
                exp, _ = e_next
                println(io, "$bold---> Missing line:$reset\n$red$exp$reset")
                break
            end
            if isnothing(e_next)
                act, _ = a_next
                println(io, "$bold---> Unexpected line:$reset\n$blue$act$reset")
                break
            end
            exp, e_state = e_next
            act, a_state = a_next
            if exp != act
                println(io, "$bold---> First differing lines:$reset")
                println(io, "$blue$exp$reset")
                println(io, "$red$act$reset")
                break
            end
            a_next = iterate(a_it, a_state)
            e_next = iterate(e_it, e_state)
        end
    end
end

function spread_compare(io, exp, act)
    println(io, "$bold   -------------------expected----------------$reset")
    println(io, exp)
    println(io, "$bold   --------------------actual-----------------$reset")
    isnothing(act) || println(io, act)
end

"Compare raw strings."
function test_string(
    expected,
    actual,
    what = "strings",
    throw = Base.throw,
)
    actual = remove_decorations(actual)
    actual == expected && return @test true # Just to +1 on the surrounding @testest.
    throw(UnmatchedStrings(what, expected, actual))
end

"Compare `Base.repr` display."
test_repr(x, expected) = test_string(expected, repr(x), "console representations")

"Compare console display."
function test_disp(x, expected)
    actual = wide_repr(x)
    test_string(expected, actual, "console displays")
end

"""
Capture the exception raised by the given expression to compare its console report display.
Fails if the expression does not raise any exception.
If provided, also test location of the first stack frame.
"""
function test_err(fn, expected, frame::Option{String} = nothing)
    try
        fn()
    catch e
        actual = sprint(showerror, e)
        test_string(expected, actual, "error messages", rethrow)
        isnothing(frame) || test_first_frame(frame)
        return @test true # +1 on the surrounding @testset when using the macro version.
    end
    errwith("Unexpected success:") do io
        println(io, "Was expecting the following error message:")
        println(io, "----------------------")
        println(io, expected)
        println(io, "----------------------")
        println(io, "But obtained $(red)$(bold)no actual error$(reset) to compare against.")
    end
end

"""
Check the location pointed by the first frame on the exception stack,
with the format "<file>:<line>".
"""
test_first_frame(exp::String) = test_first_frame(current_exceptions(), exp)
function test_first_frame(exc_stack::Base.ExceptionStack, exp::String)
    for (_, backtrace) in exc_stack
        for bt in backtrace
            frames = StackTraces.lookup(bt)
            for frame in frames
                (; file, line) = frame
                line == -1 && continue # Skip special frames that we can't control.
                act = "$file:$line"
                return test_string(exp, act,
                    "$(yellow)first stack frames$(reset)",
                    rethrow,
                )
            end
        end
    end
    throw("unreachable (right? Only special frames on the stack?)")
end

"Generate a macro version of the above for direct use within @testset."
macro genmacro(fn)
    name = Symbol(fn)
    quote
        macro $name(args...)
            src = $(esc(:__source__)) # (https://github.com/JuliaLang/julia/issues/62572)
            args = esc.(args)
            # Fake a failed @test call for surrounding @testset..
            ftest = :($($Test).@test false) #                                         <---
            ftest.args[2] = src # ..whose location is invocation site, not literally *here*.
            quote
                try
                    $($fn)($(args...))
                catch e
                    showerror(stderr, e) # Display the obtained failure report but..
                    $ftest # ..downgrade to only a failed @test to keep the testsuite going.
                end
            end
        end
    end
end
@genmacro test_string
@genmacro test_repr
@genmacro test_disp
@genmacro test_err
@genmacro test_first_frame

end
