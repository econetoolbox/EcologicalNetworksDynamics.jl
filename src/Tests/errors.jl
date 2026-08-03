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

using EcologicalNetworksDynamics: I, Display, @ErrBrand, errwith, errwrap, escall, Tests
using .Display: blue, red, yellow, black, bold, italics, reset, rept, eprintln
using .Tests.Strings: showcompare, showdiff, check_string, UnmatchedStrings, Ln, lnline

using Test

const R = Errors

"""
Generate code testing whether the given expression fails as expected.

# Arguments

  - `src::$Ln`: Where to point at in case of failure.
  - `xp` (unevaluated): The expression to be tested for failure.
  - `E` (unevaluated): The expected exception type to be collected.
  - `fields` (unevaluated): The exception exception field values.
  - `checks`: map field names (symbols) to custom check functions
    with signature `check(expected, actual)` (values)
    that throw on mismatch (see collection in module `FieldsCompare`).
    Defaults to checking type and value equality.
    Replace the function by `nothing` to ignore testing this field.
"""
function fails(src::Ln, xp, E, fields, checks;
    # Lower if already evaluated/checked.
    check_exception_type = true,
    # Provide list of non-ignored expected field names if already evaluated/checked.
    checked_enames = nothing,
)
    # Try to reduce the amount of generated quote.
    # The only irreducible part being that arguments to the following
    # *must* have been evaluated at execution time after expansion.
    # Not exactly sure how to make this part less verbose, but.. (vvv)
    _check_exception_type =
        check_exception_type ?
        E -> R.check_exception_type(src, E) :
        E -> nothing
    _checked_enames =
        isnothing(checked_enames) ?
        (E::Type, checks) -> R.check_checksmap(src, E, checks) :
        (::Type, _) -> checked_enames
    check_fields_expression(E, en) = R.check_fields_expression(src, E, en, fields)
    eval_fields(ev) = R.eval_macro_input(src, ev, fields, "expected error fields")
    wrap(e) = Base.rethrow(FailedFailureTest(src, e))
    # (^^^) ..the intent is to clarify what's happening in the generated code below.
    # Control flow can therefore wind between execution(vvv)scope and expansion(^^^)scope.
    quote
        # Most of the work from here to..
        E = $E
        $_check_exception_type(E)
        checks = $checks
        enames = $_checked_enames(E, checks)
        # ..here is either evaluated now or prior to invocation (see below).
        $check_fields_expression(E, enames)
        fields = $eval_fields(() -> $(escall(fields)))
        try
            try
                $(esc(xp)) # Evaluate the expression expected to fail.
                $throw($R.UnexpectedSuccess())
            catch e
                e isa $R.UnexpectedSuccess && R.unexpected_success(E, fields)
                e isa E || $R.unexpected_error_type(e, E, fields)
                $R.test_error_expected(e, E, fields, checks)
            end
        catch e
            $wrap(e)
        end
    end
end

"Brand specific failure case."
struct UnexpectedSuccess end

"Wrap just before toplevel to indicate macro invocation site."
struct FailedFailureTest
    src::Ln
    err
end
function Base.showerror(io::IO, e::FailedFailureTest)
    (; src, err) = e
    println(io, lnline(src))
    showerror(io, err)
end

"The regular way to call into `fails` with pre-evaluated `src` argument."
macro fails(xp, E, fields...)
    macrofails(__source__, xp, E, fields, :(;))
end

"Call by also specifying custom check functions."
macro fails_with(xp, E, checks, fields...)
    macrofails(__source__, xp, E, fields, checks)
end

function macrofails(src, xp, E, fields, checks)
    eval_E(ev) = R.eval_macro_input(src, ev, E, "expected error type")
    eval_checks(ev) = R.eval_macro_input(src, ev, checks, "fields checking functions")
    fails(src, xp,
        :($eval_E(() -> $(esc(E)))),
        fields,
        :($eval_checks(() -> $(esc(checks)))),
    )
end

"""
Generate a macro that calls into `fails` \
with pre-evaluated/checked `E` and `checks` argument.
"""
macro generrortest(name::Symbol, E, checks = :(;))
    src = __source__
    name = esc(name)
    check_checksmap(E::Type, checks) = R.check_checksmap(src, E, checks)
    eval_checks(ev) = R.eval_macro_input(src, ev, checks, "fields checking functions")
    eval_E(ev) = R.eval_macro_input(src, ev, E, "expected error type") # <^^ these happen..
    quote                                                              #   |
        E = $eval_E(() -> $(esc(E)))                                   #   |
        checks = $eval_checks(() -> $(esc(checks)))                    #   |
        enames = $check_checksmap(E, checks)                           #   |
        macro $name(xp, fields...)                                     # <-- ..outside this.
            src = $(esc(:__source__)) # (https://github.com/JuliaLang/julia/issues/62572)
            fails(src, xp, E, fields, checks;
                check_exception_type = false,
                checked_enames = enames,
            )
        end
    end
end

#-------------------------------------------------------------------------------------------
# Utils checking correct invocation of the above.

"""
Evaluate macro input and decorate any error when forwarding it up.
Useful if the given function body needs to be `esc`aped.
"""
eval_macro_input(src::Ln, eval::Function, origin, what) =
    try
        eval()
    catch e
        errwrap(e, "When evaluating $what:") do io
            println(io, lnline(src))
            println(io, "  $origin")
        end
    end

"Test (evaluated) input provided as an expected exception type."
check_exception_type(src::Ln, E) = errwith("Not an exception type:") do io
    println(io, lnline(src))
    print(io, "  ", rept(E))
end
check_exception_type(::Ln, ::Type{<:Exception}) = @test true # +1 for @testset.

"""
Check (evaluated) custom fields checks map against (evaluated) expected type expression.
Filter out ignored fields and return included ones.
"""
function check_checksmap(src::Ln, E::Type{<:Exception}, checks)
    enames = fieldnames(E)
    for cname in keys(checks)
        cname in enames || errwith("Invalid field name:.") do io
            println(io, lnline(src))
            println(
                io,
                "Exception type $italics$yellow$E$reset \
                 has no field named $bold$blue$(repr(cname))$reset.",
            )
        end
    end
    filter(n -> !(haskey(checks, n) && isnothing(checks[n])), enames)
end

"""
Assuming the above passed,
check (unevaluated) fields signature against the non-ignored fields list.
"""
function check_fields_expression(
    src::Ln,
    E::Type{<:Exception},
    expected_names::Tuple{Vararg{Symbol}},
    fields::Tuple,
)
    e, a = length.((expected_names, fields))
    e == a && return # (no +1 for @testset: this is just about invocation correctness)
    errwith("Wrong number of error fields:") do io
        println(io, lnline(src))
        se, sa = I.map(n -> n == 1 ? "" : "s", (e, a))
        println(io, "This error type requires checking $blue$e$reset field$se:")
        println(io, "  $yellow$E$black$bold$expected_names$reset")
        print(io, "but input contains $red$a$reset value$sa to be checked against:")
        for f in fields
            print(io, "\n  - $black$bold$(repr(f))$reset")
        end
    end
end

#-------------------------------------------------------------------------------------------
# Utils checking the actual exception received against expectations,
# once the macro invocation is proved correct.

unexpected_success(E::Type{<:Exception}, fields) =
    errwith("Unexpected success:") do io
        showcompare(io,
            "$yellow$E$black$fields$reset",
            "$black<no actual error obtained>$reset",
        )
    end

unexpected_error_type(err, E::Type{<:Exception}, fields) =
    errwrap(err, "Unexpected error type:") do io
        showcompare(io, "$yellow$E$blue$fields$reset", nothing)
    end

"""
Raise on mismatched exception fields.
Header is a short string to include during upgrade.
"""
@ErrBrand WrongField

"Test actual error value against (evaluated) expected fields."
function test_error_expected(err, E::Type{<:Exception}, fields, checks)
    for (name, exp) in zip(fieldnames(E), fields)
        act = getfield(err, name)
        try
            if haskey(checks, name)
                checks[name](exp, act)
            else
                FieldsCompare.default(exp, act)
            end
        catch e
            e isa WrongField || rethrow(e)
            # Unwrap to build into a fresh error.
            e = e.source
            errwith(
                "Unexpected field value:$reset $italics$(e.head):$reset",
                rethrow,
            ) do io
                field = "$blue$bold$name$reset"
                println(io, "$italics  in $yellow$E$reset.$field:")
                e.display(io)
            end
        end
        @test true # +1 test count in @testset per checked error field.
    end
end

#-------------------------------------------------------------------------------------------

"Elementary functions testing exception fields."
module FieldsCompare
    using ..R:
        errwith, errwrap, showcompare, showdiff, WrongField, rept, check_string,
        UnmatchedStrings

    "Default-compare exception fields for type and equality."
    function default(exp, act)
        type(exp, act)
        value(exp, act)
    end

    function type(exp, act)
        E, A = typeof.((exp, act))
        E === A || errwith(WrongField, "wrong type", rethrow) do io
            showcompare(io, E, A)
        end
    end

    value(exp, act) =
        exp == act || errwith(WrongField, "wrong value", rethrow) do io
            showcompare(io, repr(exp), repr(act))
        end

    "Compare string fields for equality, assuming they are error messages."
    function message(exp, act)
        exp isa String ||
            errwith(WrongField, "Not a message string to compare against:", rethrow) do io
                println(io, "  ", rept(exp))
            end
        try
            check_string(act, exp, "error messages", rethrow)
        catch e
            e isa UnmatchedStrings || rethrow(e)
            errwrap(e, WrongField, "wrong error message") do io
                showdiff(io, e.expected, e.actual)
            end
        end
    end
end

end
