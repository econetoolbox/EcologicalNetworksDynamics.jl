"""
Provides `@fails` macro and derivatives
to test whether the given expression yields the expected exception value,
without checking the exact detail of the exception display.
It is checked that an error is obtained,
that it has the expected error type,
and that it has has the expected fields values,
provided in the exception type fields order.

Among these fields,
it is default-expected that one called `mess` is `::String` (common within the package),
and this one is tested using the string checking utils above.
Others are tested using basic equality.
TODO: generalize the above by providing `(:fieldname => compare_fn)` pairs instead.

TODO: `@fails` only checks the expression *evaluation* process,
generalize again if required to also check macro *expansion* process.
"""
module Errors

using EcologicalNetworksDynamics: Display, errwith, errwrap, I, Tests, escall
using .Display: blue, red, yellow, black, bold, italics, reset, rept
using .Tests.Strings: spread_compare, test_string, UnmatchedStrings

using Test

const R = Errors

# Useful to correctly point at failed test site.
const Ln = LineNumberNode
function lnline(src::Ln)
    (; file, line) = src
    "$blue$bold@@@ $file:$line @@@$reset"
end

"""
Generate code testing whether the given expression fails as expected.

# Arguments

  - `src::$Ln`: Where to point at in case of failure.
  - `xp` (unevaluated): The expression to be tested for failure.
  - `E` (unevaluated): The expected exception type to be collected.
  - `fields` (unevaluated): The exception exception field values.
"""
function fails(src::Ln, xp, E, fields)
    # The only irreducible part being that arguments to the following
    # *must* have been evaluated at execution time after expansion.
    # Not exactly sure how to make this part less verbose, but.. (vvv)
    eval_fields(ev) = R.eval_macro_input(src, ev, fields, "expected error fields")
    check_exception_type(E) = R.check_exception_type(src, E)
    check_fields(E::Type) = R.check_fields(src, E, fields)
    unexpected_success(E, fields) = R.unexpected_success(src, E, fields)
    unexpected_error_type(err, E, fields) = R.unexpected_error_type(src, err, E, fields)
    test_error_expected(err, E, fields) = R.test_error_expected(src, err, E, fields)
    # (^^^) ..the intent is to clarify what's happening in the codegen below.
    # Control flow can therefore wind between execution(vvv)scope and expansion(^^^)scope.
    quote
        E = $E # Either evaluated here or prior to invocation (see below).
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

"The regular way to call into `fails` with pre-evaluated `src` argument."
macro fails(xp, E, fields...)
    src = __source__
    eval_E(ev) = R.eval_macro_input(src, ev, E, "expected error type")
    fails(src, xp, :($eval_E(() -> $(esc(E)))), fields)
end

"Generate a macro that calls into `fails` with pre-evaluated `E` argument."
macro generrortest(name::Symbol, E)
    src = __source__
    name = esc(name)
    eval_E(ev) = R.eval_macro_input(src, ev, E, "expected error type") # <-- this happens..
    quote                                                              #   |
        E = $eval_E(() -> $(esc(E)))                                   #   |
        macro $name(xp, fields...)                                     # <-- ..outside this.
            src = $(esc(:__source__)) # (https://github.com/JuliaLang/julia/issues/62572)
            fails(src, xp, E, fields)
        end
    end
end

#-------------------------------------------------------------------------------------------
# Utils checking correct invocation of the above.

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

"Test actual error value against (evaluated) expected fields."
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
