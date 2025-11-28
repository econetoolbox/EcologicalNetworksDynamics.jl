# The macros exposed in this module generate and execute code
# to correctly define new components, blueprints and methods,
# and check that their input makes sense.
# On incorrect input, they emit useful error messages
# either during generation="expansion" or execution of the generated code.
#
# We refer to generation as "expansion" because the generated code
# is supposed to be executed at toplevel scope
# and define new types and methods in the invocation module.
#
# Worth noting, macros here accept arguments referring to other types
# which may also have been defined with macros.
# Checking that these arguments are valid types
# is not straightforward in general because in the following..
#
#   @create_value A
#   @create_value B depends_on_value(A)
#
# .. it cannot be enforced that the second macro expansion
# will happen *after* the code resulting of the first expansion is executed.
# For instance, both expansions happen prior to any execution in the following:
#
#   begin
#     @create_value A
#     @create_value B depends_on_value(A)
#   end
#
# To avoid this becoming a problem,
# and because it does not alter the framework semantics,
# macros defined in this module only expand to trivial function calls,
# that generate code for *immediate* execution
# then throw it away so they don't actually generate any code as an output:
#
#   begin
#       create_value_fn(:A)
#       create_value_fn(:B, :(depends_on_value(A)))
#   end
#
# This approach makes us opt out of julia's automatic hygiene
# for the generated code temporary variables.
# Be careful to not pollute the invocation module's namespace with generated names.
# Also, only evaluate the passed expressions once (as the invoker expects).
#
# The following helper functions should be helpful in this respect.

# Evaluate given input in invocation module toplevel context,
# and (possibly) check against expected type.
function checked_eval(mod, xp, context, err, T = nothing)
    value = try
        mod.eval(xp)
    catch _
        err("$context: expression does not evaluate: $(repr(xp)). \
             (See error further down the exception stack.)")
    end
    isnothing(T) && return
    value isa T || err("$context: expression does not evaluate to a '$T':\n\
                        Expression: $(repr(xp))\n\
                        Result: $value ::$(typeof(value))")
    value
end

# Special-case of the above when the expression is expected to evaluate
# into a blueprint type for the given expected value type.
function eval_blueprint_type(mod, xp, V, ctx, err)
    B = checked_eval(mod, xp, ctx, err, DataType)
    Sup = Blueprint{V}
    if !(B <: Sup)
        but = B <: Blueprint ? ", but '$(Blueprint{system_value_type(B)})'" : ""
        err("$ctx: '$B' does not subtype '$Sup'$but.")
    end
    B
end

# Display input expression, its evaluation result and its resulting type.
xpres(xp, v) = "\nExpression: $(repr(xp))\nResult: $v ::$(typeof(v))"

# Same for a component type, but a singleton *instance* can be given instead.
function eval_component(mod, xp, V, ctx, err)
    C = checked_eval(mod, xp, ctx, err, Any)
    check_component_type_or_instance(xp, C, V, ctx, err)
end
# Factorize away for reuse within `eval_dependency` in @method macro.
function check_component_type_or_instance(xp, C, V, ctx, err)
    Sup = Component{V}
    if C isa Type
        if !(C <: Sup)
            comp = if C <: Component
                "'$Component{$V}', but of '$Component{$(system_value_type(C))}'"
            else
                "'$Component'"
            end
            err("$ctx: expression does not evaluate \
                 to a subtype of $comp:$(xpres(xp, C))")
        end
        C
    else
        c = C # Actually an instance.
        if !(c isa Sup)
            but = c isa Component ? ", but for '$(system_value_type(c))'" : ""
            err("$ctx: expression does not evaluate \
                 to a component for '$V'$but:$(xpres(xp, c))")
        end
        typeof(c)
    end
end

# Same, but without checking against a prior expectation for the system value type.
function eval_component(mod, xp, ctx, err)
    C = checked_eval(mod, xp, ctx, err, Any)
    check_component_type_or_instance(xp, C, ctx, err)
end
function check_component_type_or_instance(xp, C, ctx, err)
    if C isa Type
        C <: Component || err("$ctx: expression does not evaluate \
                               to a subtype of $Component:$(xpres(xp, C))")
        C
    else
        c = C # Actually an instance.
        c isa Component || err("$ctx: expression does not evaluate \
                                to a component:$(xpres(xp, c))")
        typeof(c)
    end
end

# Collect 'component => reason' pairs (from macro input).
function eval_comp_reasons(mod, xps, V, ctx, err)
    res = []
    for req in xps
        # Set requirement reason to 'nothing' if unspecified.
        (false) && (local comp, reason) # (reassure JuliaLS)
        @capture(req, comp_ => reason_)
        if isnothing(reason)
            comp = req
        else
            reason = checked_eval(mod, reason, "$ctx reason", err, String)
        end
        comp = eval_component(mod, comp, V, ctx, err)
        push!(res, comp => reason)
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

# The macro expands without error,
# but during execution of the generated code,
# we figure that it had been given invalid arguments.
struct ItemMacroError <: Exception
    category::Symbol # (:component, :blueprint or :method)
    # Nothing if not yet determined,
    # Symbol if not yet defined.
    item::Union{Nothing,Type,Function,Symbol}
    src::LineNumberNode
    message::String
end

function Base.showerror(io::IO, e::ItemMacroError)
    if isnothing(e.item)
        print(io, "In @$(e.category) definition: ")
    else
        print(io, "In @$(e.category) definition for '$(e.item)': ")
    end
    println(io, crayon"blue", "$(e.src.file):$(e.src.line)", crayon"reset")
    println(io, e.message)
end

struct ConflictMacroError <: Exception
    src::LineNumberNode
    message::String
end
function Base.showerror(io::IO, e::ConflictMacroError)
    print(io, "In @conflicts definition: ")
    println(io, crayon"blue", "$(e.src.file):$(e.src.line)", crayon"reset")
    println(io, e.message)
end
