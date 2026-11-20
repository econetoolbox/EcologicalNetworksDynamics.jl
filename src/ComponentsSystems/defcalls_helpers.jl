# The methods exposed in this module used to be wrapped in sophisticated macros
# that did not end up adding much value to the interface
# but did complicate maintenance a lot.
# They have been dropped in favour of regular function calls like so:
#
#     define_component(mod, :A, ..)
#     define_blueprint(mod, :B, ..)
#
# Which internally just generate component code and evaluate it within the passed `mod`ule.
#
# This approach makes us opt out of julia's automatic hygiene
# for the generated code temporary variables.
# Be careful to not pollute the `mod`ule's namespace with generated names.
#
# The following helper functions ease the definition / checking of the overall interface.

# Evaluate given input against expected type.
function check_type(v, context, err, T)
    v isa T || err("$context:\nExpected $T, received instead: $(rept(v))")
    v
end

# Special-case of the above when the expression is expected to evaluate
# into a blueprint type for the given expected value type.
function check_blueprint_type(value, V, ctx, err)
    BP = check_type(value, ctx, err, DataType)
    Sup = Blueprint{V}
    if !(BP <: Sup)
        but = BP <: Blueprint ? ", but `$(Blueprint{system_value_type(BP)})`" : ""
        err("$ctx:\n`$BP` does not subtype `$Sup`$but.")
    end
    BP
end

# Special-case unexpected component value display.
compr(cp) = ": " * rept(cp)
compr(cp::Component) = ": $(compdisplay(cp))  ::$(compdisplay(typeof(cp)))"

# Same for a component type, but a singleton *instance* can be given instead.
function check_component(CP, V, ctx, err)
    Sup = Component{V}
    if CP isa Type
        if !(CP <: Sup)
            comp = if CP <: Component
                "`$Component{$V}`, but of `$Component{$(system_value_type(CP))}`"
            else
                "`$Component`"
            end
            err("$ctx:\nNot a subtype of $comp$(compr(CP))")
        end
        CP
    else
        cp = CP # Actually an instance.
        if !(cp isa Sup)
            but = cp isa Component ? ", but for `$(system_value_type(cp))`" : ""
            err("$ctx:\nNot a component for `$V`$but$(compr(CP))")
        end
        typeof(cp)
    end
end

# Same, but without checking against a prior expectation for the system value type.
function check_component(CP, ctx, err)
    if CP isa Type
        CP <: Component || err("$ctx:\nNot a subtype of $Component$(compr(CP))")
        CP
    else
        cp = CP # Actually an instance.
        cp isa Component || err("$ctx:\nNot a component$(compr(CP))")
        typeof(cp)
    end
end

# Check, expand and collect 'component => reason' requirement pairs,
# setting reason to 'nothing' if unspecified.
function check_reasons(input, V, ctx, err)
    res = Pair{CompType{V},Reason}[]
    for (i, req) in enumerate(input)
        comp, reason = try
            comp, reason = req
            comp, reason
        catch _
            (req, nothing)
        end
        check_type(reason, "$ctx reasons[$i]", err, Option{String})
        CP = check_component(comp, V, ctx, err)
        push!(res, CP => reason)
    end
    res
end

# Guard against redundancy in a list like collected above.
function triangular_vertical_guard(comp_reasons, V, xerr)
    reqs = CompsReasons{V}()
    for (Req, reason) in comp_reasons
        # Triangular-check against redundancies,
        # checking through abstract types.
        for (Already, _) in reqs
            vertical_guard(
                Req,
                Already,
                () -> xerr("Requirement $(cd(Req)) is specified twice."),
                (Sub, Sup) ->
                    xerr("Requirement $(cd(Sub)) is also specified as $(cd(Sup))."),
            )
        end
        reqs[Req] = reason
    end
    reqs
end

# ==========================================================================================
# Dedicated exceptions.

# Invalid item received.
struct ItemError <: Exception
    category::Symbol # (:component, :blueprint or :method)
    # Nothing if not yet determined,
    # Symbol if not yet defined.
    item::Union{Type,Function,Symbol}
    mess::String
end

function Base.showerror(io::IO, e::ItemError)
    print(io, "In $(e.category) definition for `$(e.item)`:\n")
    println(io, e.mess)
end

struct ConflictError <: Exception
    mess::String
end
function Base.showerror(io::IO, e::ConflictError)
    print(io, "In conflicts definition:\n")
    println(io, e.mess)
end
