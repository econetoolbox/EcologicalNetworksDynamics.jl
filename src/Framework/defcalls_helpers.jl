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

# Display input expression, its evaluation result and its resulting type.
valr(value) = ": $(repr(value)) ::$(typeof(value))"

# Evaluate given input against expected type.
function check_type(v, context, err, T)
    v isa T || err("$context:\nExpected $T, received instead$(valr(v))")
    v
end

# Special-case of the above when the expression is expected to evaluate
# into a blueprint type for the given expected value type.
function check_blueprint_type(value, V, ctx, err)
    B = check_type(value, ctx, err, DataType)
    Sup = Blueprint{V}
    if !(B <: Sup)
        but = B <: Blueprint ? ", but `$(Blueprint{system_value_type(B)})`" : ""
        err("$ctx:\n`$B` does not subtype `$Sup`$but.")
    end
    B
end

# Same for a component type, but a singleton *instance* can be given instead.
function check_component(C, V, ctx, err)
    Sup = Component{V}
    if C isa Type
        if !(C <: Sup)
            comp = if C <: Component
                "`$Component{$V}`, but of `$Component{$(system_value_type(C))}`"
            else
                "`$Component`"
            end
            err("$ctx:\nNot a subtype of $comp$(valr(C))")
        end
        C
    else
        c = C # Actually an instance.
        if !(c isa Sup)
            but = c isa Component ? ", but for `$(system_value_type(c))`" : ""
            err("$ctx:\nNot a component for `$V`$but$(valr(C))")
        end
        typeof(c)
    end
end

# Same, but without checking against a prior expectation for the system value type.
function check_component(C, ctx, err)
    if C isa Type
        C <: Component || err("$ctx:\nNot a subtype of $Component$(valr(C))")
        C
    else
        c = C # Actually an instance.
        c isa Component || err("$ctx:\nNot a component$(valr(C))")
        typeof(c)
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
        C = check_component(comp, V, ctx, err)
        push!(res, C => reason)
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
                () -> xerr("Requirement $Req is specified twice."),
                (Sub, Sup) -> xerr("Requirement $Sub is also specified as $Sup."),
            )
        end
        reqs[Req] = reason
    end
    reqs
end


# Check whether the expression is a `raw.identifier.path`.
# (Useful for properties accesses.)
function is_identifier_path(xp)
    xp isa Symbol && return true
    if xp isa Expr
        xp.head == :. || return false
        path, last = xp.args
        last isa QuoteNode || return false
        is_identifier_path(path) && is_identifier_path(last.value)
    else
        false
    end
end

# Collect path the 'forward' way: :(a.b.c.d) -> [:a, :b, :c, :d].
# (assuming it has been checked by the above function)
function collect_path(path; res = [])
    if path isa Symbol
        push!(res, path)
    else
        prefix, last = path.args
        collect_path(prefix; res)
        collect_path(last.value; res)
    end
    res
end

# Again, assuming the expression has been checked for being a path.
function last_in_path(path)
    path isa Symbol && return path
    path.args[2].value
end

# ==========================================================================================
# Dedicated exceptions.

# Invalid item received.
struct ItemError <: Exception
    category::Symbol # (:component, :blueprint or :method)
    # Nothing if not yet determined,
    # Symbol if not yet defined.
    item::Union{Type,Function,Symbol}
    message::String
end

function Base.showerror(io::IO, e::ItemError)
    print(io, "In $(e.category) definition for `$(e.item)`:\n")
    println(io, e.message)
end

struct ConflictError <: Exception
    message::String
end
function Base.showerror(io::IO, e::ConflictError)
    print(io, "In conflicts definition:\n")
    println(io, e.message)
end
