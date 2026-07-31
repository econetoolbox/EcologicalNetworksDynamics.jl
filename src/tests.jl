module Tests

using EcologicalNetworksDynamics: Display, I, EN, errwith, errwrap, ErrWrap, Option
using .Display:
    blue, black, red, bold, yellow, italics, reset, wide_repr, eprint, eprintln, rept

using Test
using StringManipulation: remove_decorations

const T = Tests # /!\ Not to be confused with `Base.Test` also in this namespace.

# ==========================================================================================
"""
Compare actual vs expected console displays, "snapshot-testing" style,
with a helful summary displayed in case of mismatch.
Report by raising.
"""
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

#-------------------------------------------------------------------------------------------

"Test short string display."
test_repr(x, expected) = test_string(expected, repr(x), "console representations")

"Test long string display."
function test_disp(x, expected)
    actual = wide_repr(x)
    test_string(expected, actual, "console displays")
end

# ==========================================================================================
"""
Capture expression error to test the displayed error message
If provided, also test location of the first stack frame, assuming `ErrWrap` is thrown.
(this function version is better-suited for use outside `@testset`)
"""
function test_err(fn, expected, frame::Option{String})
    try
        fn()
    catch e
        actual = sprint(showerror, e)
        test_string(expected, actual, "error messages", rethrow)
        isnothing(frame) || test_first_frame(e, frame)
        return @test true # +1 on the surrounding @testset.
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
Macro version of the above for direct use within @testset.
in case of failure:
will not break the set with a bubling exception,
will point to the right test failure location.
"""
macro test_err(f, e, r = nothing)
    f, e, r = esc.((f, e, r))
    # Fake failed @test location at invocation site, not literally here.
    mcall = :($Test.@test false)
    mcall.args[2] = __source__
    quote
        try
            $T.test_err($f, $e, $r)
        catch e
            showerror(stderr, e)
            $mcall
        end
    end
end

"""
Check the location pointed by the first frame on the given stack,
with the format "<file>:<line>".
"""
function test_first_frame(exc_stack::Base.ExceptionStack, exp::String)
    for (exc, backtrace) in exc_stack
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
test_first_frame(_, exp::String) = test_first_frame(current_exceptions(), exp)
# Assume this is what is expected when checking a plain wrapped/forwarded unknown error.
test_first_frame(e::ErrWrap, exp) = test_first_frame(e.stack, exp) # ONHOLD?

# ==========================================================================================
"""
Test whether the given expression yields the correct exception value,
without checking the exact detail of the exception display.
It is checked that an error is obtained,
that it has the expected error type,
and it has has the expected fields values, provided in field order.
Among these fields,
it is default-expected that one called `mess` is `::String` (common within the package),
and this one is tested using the string checking utils above.
Others are tested using basic equality.
TODO: this only checks the expression *evaluation* process,
generalize again if required to also check macro *expansion* process.
"""
macro fails(xp, E, fields...)
    src, mod = __source__, __module__
    # Reduce generated code size by capturing most of the desired behaviour here.
    # The only irreducible part being that arguments to the following
    # *must* have been evaluated at execution time after expansion.
    # Not exactly sure how to make this part less verbose, but.. (vvv)
    eval_E(ev) = T.eval_macro_input(src, ev, E, "expected error type")
    eval_fields(ev) = T.eval_macro_input(src, ev, fields, "expected error fields")
    check_exception_type(E) = T.check_exception_type(src, E)
    check_fields(E::Type) = T.check_fields(src, E, fields)
    unexpected_success(E, fields) = T.unexpected_success(src, E, fields)
    unexpected_error_type(err, E, fields) = T.unexpected_error_type(src, err, E, fields)
    test_error_expected(err, E, fields) = T.test_error_expected(src, err, E, fields)
    # (^^^) ..the intent is to clarify what's happening in the codegen below.
    # Control flow can therefore wind between execution(vvv)scope and expansion(^^^)scope.
    quote
        E = $eval_E(() -> $(esc(E)))
        $check_exception_type(E)
        $check_fields(E)
        fields = $eval_fields(() -> $(escall(fields)))
        success = try
            $(esc(xp)) # Evaluate the expression expected to fail.
            true
        catch err
            if err isa E
                $test_error_expected(err, E, fields)
            else
                $unexpected_error_type(err, E, fields)
            end
            false
        end
        success && $unexpected_success(E, fields)
    end
end
"`:((esc(a), esc(b))) != (:(esc(a)), :(esc(b)))` so esc.((a, b)) won't do."
escall(xp::Tuple) = Expr(:tuple, esc.(xp)...)

#-------------------------------------------------------------------------------------------
# Utils checking correct invocation of the above.

const Ln = LineNumberNode
function lnline(src::Ln)
    (; file, line) = src
    "$blue$bold@@@ $file:$line @@@$reset"
end

"""
Evaluate macro input and decorate any error when forwarding it up.
Useful if the given function body needs to be `esc`aped.
"""
function eval_macro_input(src::Ln, eval::Function, xp, what)
    try
        eval()
    catch e
        errwrap(e, "When evaluating $what:") do io
            println(io, lnline(src))
            println(io, "  $xp")
        end
    end
end

"Test (evaluated) input provided as an expected exception type."
check_exception_type(src::Ln, E) = errwith("Not an exception type:") do io
    println(io, lnline(src))
    print(io, "  ", rept(E))
end
check_exception_type(::Ln, ::Type{<:Exception}) = @test true # +1 on surrounding @testset.

"Check (unevaluated) fields signature vs. (evaluated) expected error type."
function check_fields(
    src::Ln,
    E::Type{<:Exception},
    fields::Tuple,
)
    enames = fieldnames(E)
    e, a = length.((enames, fields))
    e == a && return # (no +1 on @testset: this is just about invocation correctness)
    errwith("Wrong number of error fields:") do io
        println(io, lnline(src))
        se, sa = I.map(n -> n == 1 ? "" : "s", (e, a))
        println(io, "This error type requires checking $blue$e$reset field$se:")
        println(io, "  $yellow$E$black$bold$enames$reset")
        print(io, "but input contains $red$a$reset value$sa to be checked against:")
        for f in fields
            print(io, "\n  - $black$bold$(repr(f))$reset")
        end
    end
end

#-------------------------------------------------------------------------------------------
# Utils checking the actual exception received against expectations,
# once the macro invocation is proved correct.

unexpected_success(src::Ln, E::Type{<:Exception}, fields) =
    errwith("Unexpected success:") do io
        println(io, lnline(src))
        spread_compare(io,
            "$yellow$E$blue$fields$reset",
            "$red<no actual error obtained>$reset",
        )
    end

unexpected_error_type(src::Ln, err, E::Type{<:Exception}, fields) =
    errwrap(err, "Unexpected error type:") do io
        println(io, lnline(src))
        spread_compare(io, "$yellow$E$blue$fields$reset", nothing)
    end

"""
Verify actual error value against (evaluated) expected fields.
"""
function test_error_expected(src::Ln, err, E::Type{<:Exception}, fields)
    for (name, exp) in zip(fieldnames(E), fields)
        act = getfield(err, name)
        if name == :mess # Special-cased.
            exp isa String ||
                errwith("Not a message string to compare against:", rethrow) do io
                    println(io, lnline(src))
                    println("  ", rept(exp))
                end
            try
                test_string(exp, act, "error message fields", rethrow)
                continue
            catch e
                e isa UnmatchedStrings || rethrow(e)
                errwrap(e, "Unexpected error message:") do io # Prepend context.
                    println(io, lnline(src))
                    println(io, "$(italics)in $yellow$E$reset$italics$reset:")
                end
            end
        end
        act == exp ||
            errwith("Unexpected field $black$bold$(repr(name))$reset value:", rethrow) do io
                println(io, lnline(src))
                println(io, "$(italics)in $yellow$E$reset$italics$reset:")
                spread_compare(io, "  " * rept(exp), "  " * rept(act))
            end
        @test true # +1 test count in @testset per checked error field.
    end
end

end
