module Tests

using EcologicalNetworksDynamics: Display, I, EN
using .Display: blue, black, red, bold, yellow, italics, reset, wide_repr, eprint, eprintln

using Test
using StringManipulation: remove_decorations

# ==========================================================================================
"""
Compare actual vs expected console displays, "snapshot-testing" style,
with a helful summary displayed in case of mismatch.
"""
function compare_strings(expected, actual, what = "strings"; preamble = () -> ())
    actual_decorated = actual
    actual = remove_decorations(actual)
    actual == expected && return true
    preamble() # Use to display information prior to error report.
    eprintln("$(bold)CHECK FAILED:$reset The two $what differ:")
    if !('\n' in actual || '\n' in expected)
        # Single-line display.
        eprintln("$(blue)expected:$reset $expected\n\
                  $(red)  actual:$reset $actual_decorated")
    else
        # Multiline display.
        spread_compare_display(expected, actual_decorated)
        a_it, e_it = eachsplit.((actual, expected), '\n')
        a_next = iterate(a_it)
        e_next = iterate(e_it)
        while true
            isnothing(a_next) && isnothing(e_next) && throw("Should be different, right?")
            if isnothing(a_next)
                exp, _ = e_next
                println("$bold   Missing line:$reset\n$red$exp$reset")
                break
            end
            if isnothing(e_next)
                act, _ = a_next
                println("$bold   Unexpected line:$reset\n$blue$act$reset")
                break
            end
            exp, e_state = e_next
            act, a_state = a_next
            if exp != act
                println("$bold   First differing lines:$reset\n\
                        $blue$exp$reset\n\
                        $red$act$reset")
                break
            end
            a_next = iterate(a_it, a_state)
            e_next = iterate(e_it, e_state)
        end
    end
    false
end
spread_compare_display(exp, act) =
    eprintln("$bold   -------------------expected----------------$reset\n\
              $exp\n\
              $bold   --------------------actual-----------------$reset\n\
              $act")

#-------------------------------------------------------------------------------------------

"Test short string display."
is_repr(x, expected) = compare_strings(expected, repr(x), "console representations")

"Test long string display."
function is_disp(x, expected)
    actual = wide_repr(x)
    compare_strings(expected, actual, "console displays")
end

"Test error message."
function is_err(fn, expected)
    try
        fn()
    catch e
        actual = sprint(showerror, e)
        return compare_strings(expected, actual, "error messages")
    end
    eprintln("$(red)$(bold)Unexpected success.$(reset) \
              Was expecting the following error message:\n\
              ----------------------\n\
              $expected\n\
              ----------------------\n\
              But obtained $(red)$(bold)no actual error$(reset) to compare against.")
    false
end

# ==========================================================================================
"""
Check whether the given expression fails
with the expectetd error type,
and whether that error type has the expected fields values,
provided in field order.
Among these fields,
it is default-expected that one called `mess` is `::String` (common within the package),
and this one is tested using the sophisticated string comparison utils above by default.
Others and are tested using basic equality by default.
TODO: this only checks the expression *evaluation* process,
generalize again if required to checking its macro *expansion* process.
"""
function does_fail(mod, src, xp::Expr, E::Type{<:Exception}, fields...)
    # First check that the correct number of field names is being tested.
    enames = fieldnames(E)
    e, a = length.((enames, fields))
    if e != a
        display(src)
        se, sa = I.map(n -> n == 1 ? "" : "s", (e, a))
        eprintln("This error type requires checking $blue$e$reset field$se:\n  \
                    $yellow$E$black$bold$enames$reset\n\
                  but input contains $red$a$reset value$sa to be checked against:")
        for f in fields
            eprintln("  - $black$bold$(repr(f))$reset")
        end
        return false
    end
    try
        mod.eval(xp)
    catch err
        if err isa E
            for (i, (name, exp)) in enumerate(zip(fieldnames(E), fields))
                act = getfield(err, name)
                if name == :mess
                    compare_strings(
                        exp,
                        act,
                        "error message fields\n$(italics)in $yellow$E$reset$italics$reset";
                        preamble = () -> display(src),
                    ) &&
                        continue
                    return false
                end
                if act != exp
                    display(src)
                    eprint(
                        "$red$(bold)Unexpected field $black$bold$(repr(name))$reset value\n\
                         $(italics)in $yellow$E$reset$italics$reset:\n",
                    )
                    spread_compare_display(
                        "$(repr(exp)) ::$(typeof(exp))",
                        "$(repr(act)) ::$(typeof(act))",
                    )
                    return false
                end
            end
            return true
        end
        display(src)
        eprintln("$(red)$(bold)Unexpected error type:$(reset)")
        spread_compare_display(
            "$yellow$E$blue$fields$reset",
            "$red$(wide_repr(err))$reset, saying:",
        )
        # Checking the stack trace is useful then to figure
        # where that unexpected error comes from.
        for (exc, bt) in current_exceptions()
            showerror(stderr, exc, bt)
            eprintln()
        end
        return false
    end
    display(src)
    eprintln("$(red)$(bold)Unexpected success:$(reset)")
    spread_compare_display(
        "$yellow$E$blue$fields$reset",
        "$red<no actual error obtained>$reset",
    )
    false
end
function display(src::LineNumberNode)
    (; file, line) = src
    eprintln("$blue$bold@@@ $file:$line @@@$reset")
end

#-------------------------------------------------------------------------------------------
# Convenience macros for the above.

macro does_fail(xp, E, fields...)
    mod, src = __module__, __source__
    E = mod.eval(E)
    fields = map(mod.eval, fields)
    (xp, src) = Meta.quot.((xp, src))
    quote
        $Test.@test does_fail($mod, $src, $xp, $E, $fields...)
    end
end

# Generate convenience macros whose name make it unnecessary to also input error type.
macro typefails(name, E)
    E = __module__.eval(E)
    quote
        macro $name(xp, fields...)
            #  https://github.com/JuliaLang/julia/issues/62572
            src, mod = $(esc(:__source__)), $(esc(:__module__))
            fields = map(mod.eval, fields)
            xp = quote
                $Tests.@does_fail($xp, $($E), $(fields...))
            end
            # Inject our source as the first macro call argument.
            # /!\ This means that any error in the above quote ^^^
            # will be hard to track down here from the stacktrace
            # because user will be pointed towards invokation site instead.
            xp.args[2].args[2] = src
            xp
        end
    end
end

@typefails netfails EN.Networks.NetworkError

end
