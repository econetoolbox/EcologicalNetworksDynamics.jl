# The macros exposed in this module
# generate code to correctly define new components, blueprints and methods,
# and check that their input make sense.
# On incorrect input, they emit
# useful error messages either during expansion
# or execution of the generated code.
#
# In particular, they accept arguments referring to
# other types within the same invocation module,
# which may also have been defined with macros.
# Checking that these arguments are valid types
# is not straightforward then,
# because in the following:
#
#   @create_type A
#   @create_type B depends_on_type(A)
#
# It cannot be enforced that the second macro expansion
# will happen *after* the code resulting of the first expansion is executed.
# For instance, both expansions happen before any execution in the following:
#
#   begin
#     @create_type A
#     @create_type B depends_on_type(A)
#   end
#
# As a consequence, it cannot be checked that `A`
# is a valid reference to an existing type during macro expansion.
# This check must therefore be performed during generated code execution,
# and macros must emit code for that.
# When developping these macros,
# be careful that the emitted code
# should enforce hygiene with respect to their temporary variables,
# and evaluate expressions only once (as the invoker expects)
# unless the expressions can be assumed to have no side effects
# like `raw.identifiers.paths`.
#
# The following helper functions should be helpful in this respect.

# In general, these macros are expected to only be invoked in
# user's modules toplevel scopes.
# So their input is evaluated in the invocation module's toplevel scope.
# However, this prevents them from being tested against types and methods
# defined within `@testset` blocks, because these do introduce local scopes.
# Raise this flag when doing so, just as a hack for testing comfort.
LOCAL_MACROCALLS = false

# Generate code checking evaluation of invoker's expression, in invocation context.
# Optionally specify a type for the evaluation result to be checked against.
function to_value(mod, expression, context, error_out, type = nothing)
    evcode = if LOCAL_MACROCALLS
        # Evaluate as given in local invocation scope.
        esc(expression)
    else
        # Evaluate at toplevel scope of invocation module.
        :($Core.eval($mod, $(Meta.quot(expression))))
    end
    ev = :(
        try
            $evcode
        catch _
            $error_out($"$context: expression does not evaluate: $(repr(expression)). \
                        (See error further down the exception stack.)")
        end
    )
    isnothing(type) || (
        ev = quote
            val = $ev
            val isa $type || $error_out(
                "$($context): expression does not evaluate to a '$($type)':\n\
                 Expression: $($(repr(expression)))\n\
                 Result: $val ::$(typeof(val))",
            )
            val
        end
    )
    ev
end

# Special-case of the above when the expression is expected to evaluate
# into a blueprint type for the given expected value type.
function to_blueprint_type(mod, xp, value_type_var, ctx, xerr)
    quote
        B = $(to_value(mod, xp, ctx, xerr, DataType))
        Sup = Blueprint{$value_type_var}
        if !(B <: Sup)
            but = B <: Blueprint ? ", but '$(Blueprint{system_value_type(B)})'" : ""
            $xerr("$($ctx): '$B' does not subtype '$Sup'$but.")
        end
        B
    end
end

# Display input expression, its evaluation result and its resulting type.
xpres(xp, v) = "\nExpression: $(repr(xp))\nResult: $v ::$(typeof(v))"

# Same for a component type, but a singleton *instance* can be given instead.
function to_component(mod, xp, value_type_var, ctx, xerr)
    quote
        C = $(to_value(mod, xp, ctx, xerr, Any))
        $(check_component_type_or_instance(xp, :C, value_type_var, ctx, xerr))
    end
end
# Factorize away for reuse within `to_dependency` in @method macro.
function check_component_type_or_instance(xp, C::Symbol, V::Symbol, ctx, xerr)
    qxp = Meta.quot(xp)
    quote
        C = $C
        V = $V
        Sup = Component{V}
        if C isa Type
            if !(C <: Sup)
                comp = if C <: Component
                    "'$Component{$V}', but of '$Component{$(system_value_type(C))}'"
                else
                    "'$Component'"
                end
                $xerr("$($ctx): expression does not evaluate \
                       to a subtype of $comp:$(xpres($qxp, C))")
            end
            C
        else
            c = C # Actually an instance.
            if !(c isa Sup)
                but = c isa Component ? ", but for '$(system_value_type(c))'" : ""
                $xerr("$($ctx): expression does not evaluate \
                       to a component for '$V'$but:$(xpres($qxp, c))")
            end
            typeof(c)
        end
    end
end

# Same, but without checking against a prior expectation for the system value type.
function to_component(mod, xp, ctx, xerr)
    quote
        C = $(to_value(mod, xp, ctx, xerr, Any))
        $(check_component_type_or_instance(xp, :C, ctx, xerr))
    end
end
function check_component_type_or_instance(xp, C::Symbol, ctx, xerr)
    qxp = Meta.quot(xp)
    quote
        C = $C
        if C isa Type
            C <: Component || $xerr("$($ctx): expression does not evaluate \
                                     to a subtype of $Component:$(xpres($qxp, C))")
            C
        else
            c = C # Actually an instance.
            c isa Component || $xerr("$($ctx): expression does not evaluate \
                                      to a component:$(xpres($qxp, c))")
            typeof(c)
        end
    end
end

# Collect 'component => reason' pairs (as checked expressions again).
function to_comp_reasons(mod, xps, V, ctx, xerr)
    res = :([])
    for req in xps
        # Set requirement reason to 'nothing' if unspecified.
        (false) && (local comp, reason) # (reassure JuliaLS)
        @capture(req, comp_ => reason_)
        if isnothing(reason)
            comp = req
        else
            reason = to_value(mod, reason, "$ctx reason", xerr, String)
        end
        comp = to_component(mod, comp, V, "$ctx", xerr)
        req = :($comp => $reason)
        push!(res.args, req)
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
# (If so, then we assume it produces no side effect
# so it is okay to have it evaluated multiple times
# within the generated code.)
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

# Append path to a module,
# not straightforward because with U = :(a.b) and V = :(c.d),
# then :($U.$V) is *not* :(a.b.c.d) but :(a.b.:(c.d)) and most likely unusable.
# But cat_path(U, V) *is* :(a.b.c.d).
function cat_path(mod, path::Expr)
    # Collect all path steps.
    steps = Symbol[]
    current = path
    err() = argerr("Not a raw path of identifiers: $(repr(path)).")
    while !(current isa Symbol)
        current.head == :. || err()
        current, step = current.args
        step isa QuoteNode || err()
        step.value isa Symbol || err()
        push!(steps, step.value)
    end
    push!(steps, current)
    # Construct final expression with reverse read.
    res = mod
    for step in reverse(steps)
        res = :($res.$step)
    end
    res
end
# Trivial case.
cat_path(mod, id::Symbol) = :($mod.$id)

# ==========================================================================================
# Dedicated exceptions.

# User provides invalid macro arguments.
struct ItemMacroParseError <: Exception
    category::Symbol # (:component, :blueprint or :method)
    src::LineNumberNode # Locate macro invocation in user source code.
    message::String
end

function Base.showerror(io::IO, e::ItemMacroParseError)
    print(io, "In @$(e.category) macro expansion: ")
    println(io, crayon"blue", "$(e.src.file):$(e.src.line)", crayon"reset")
    println(io, e.message)
end

# The macro expands without error,
# but during execution of the generated code,
# we figure that it had been given invalid arguments.
struct ItemMacroExecError <: Exception
    category::Symbol # (:component, :blueprint or :method)
    item::Union{Nothing,Type,Function,Symbol} # Nothing if not yet determined.
    src::LineNumberNode
    message::String
end

function Base.showerror(io::IO, e::ItemMacroExecError)
    if isnothing(e.item)
        print(io, "In expanded @$(e.category) definition: ")
    else
        print(io, "In expanded @$(e.category) definition for '$(e.item)': ")
    end
    println(io, crayon"blue", "$(e.src.file):$(e.src.line)", crayon"reset")
    println(io, e.message)
end

#-------------------------------------------------------------------------------------------
# Same duo for @conflicts macro
struct ConflictMacroParseError <: Exception
    src::LineNumberNode
    message::String
end

function Base.showerror(io::IO, e::ConflictMacroParseError)
    print(io, "In @conflicts macro expansion: ")
    println(io, crayon"blue", "$(e.src.file):$(e.src.line)", crayon"reset")
    println(io, e.message)
end

struct ConflictMacroExecError <: Exception
    src::LineNumberNode
    message::String
end
function Base.showerror(io::IO, e::ConflictMacroExecError)
    print(io, "In @conflicts definition: ")
    println(io, crayon"blue", "$(e.src.file):$(e.src.line)", crayon"reset")
    println(io, e.message)
end
