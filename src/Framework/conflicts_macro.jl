# Convenience macro for specifying a set of conflicting components,
# and optionally some of the reasons they conflict.
#
# Full use:
#
#     @conflicts(
#         A => (B => "reason", C => "reason"),
#         B => (A => "reason", C => "reason'),
#         C => (A => "reason", B => "reason"),
#     )
#
# Only the keys are required, and any reason can be omitted:
#
#     @conflicts(
#         A,
#         B => (C => "reason"),
#         C,
#     )
#
# Minimal use: @conflicts(A, B, C)
macro conflicts(input...)
    conflicts_macro(__module__, __source__, input...)
end
export @conflicts

# Extract function to ease debugging with Revise.
function conflicts_macro(__module__, __source__, input...)

    # Push resulting generated code to this variable.
    res = quote end
    push_res!(xp) = xp.head == :block ? append!(res.args, xp.args) : push!(res.args, xp)

    # Raise *during expansion* if parsing fails.
    perr(mess) = throw(ConflictMacroParseError(__source__, mess))

    # Raise *during execution* if the macro was invoked with inconsistent input.
    src = Meta.quot(__source__)
    push_res!(quote
        xerr = (mess) -> throw(ConflictMacroExecError($src, mess))
    end)

    # Convenience wrap.
    tovalue(xp, ctx, type) = to_value(__module__, xp, ctx, :xerr, type)
    tocomp_novaluetype(xp, ctx) = to_component(__module__, xp, ctx, :xerr)
    tocomp(xp, ctx) = to_component(__module__, xp, :ValueType, ctx, :xerr)

    #---------------------------------------------------------------------------------------
    # Parse macro input,
    # while also generating code checking invoker input within invocation context.

    length(input) == 0 && perr("No macro arguments provided. \
                                Example usage:\n\
                                |  @conflicts(A, B, ..)\n\
                                ")


    # Infer the underlying system value type from the first argument.
    first_entry = nothing
    entries = :([])
    for entry in input

        (false) && (local comp, conf, invalid, reasons, mess) # (reassure JuliaLS)
        #! format: off
        @capture(entry,
            (comp_ => (reasons__,)) |
            (comp_ => [reasons__]) |
            (comp_ => (conf_ => mess_)) | # Special-case single reason without comma.
            (comp_ => invalid_) |
            comp_
        )
        #! format: on
        isnothing(conf) || (reasons = [:($conf => $mess)])
        isnothing(invalid) || perr("Not a list of conflict reasons: $(repr(invalid)).")
        isnothing(reasons) && (reasons = [])

        if isnothing(first_entry)
            ctx = "First conflicting entry"
            push_res!(quote
                First = $(tocomp_novaluetype(comp, ctx))
                ValueType = system_value_type(First)
            end)
            first_entry = comp
            comp = :First
        else
            comp = tocomp(comp, "Conflicting entry")
        end

        reasons_xp = :([])
        for reason in reasons
            @capture(reason, (conf_ => mess_))
            isnothing(conf) &&
                perr("Not a `Component => \"reason\"` pair: $(repr(reason)).")
            conf = tocomp(conf, "Reason reference")
            mess = tovalue(mess, "Reason message", String)
            push!(reasons_xp.args, :($conf, $mess))
        end

        push!(entries.args, :($comp, $reasons_xp))

    end

    length(entries.args) == 1 &&
        perr("At least two components are required to declare a conflict \
              not only $(repr(first_entry)).")

    # Declare all conflicts, checking that provided reasons do refer to listed conflicts.
    push_res!(
        quote
            entries = $entries
            comps = CompType{ValueType}[first(e) for e in entries]
            keys = OrderedSet{CompType{ValueType}}(comps)
            for (a, reasons) in entries
                for (b, message) in reasons
                    b in keys ||
                        xerr("Conflict reason does not refer to a component listed \
                              in the same @conflicts invocation: $b => $(repr(message)).")
                    declare_conflict(a, b, message, xerr)
                end
            end
            declare_conflicts_clique(xerr, comps)
        end,
    )

    # Avoid confusing/leaky return type from macro invocation.
    push_res!(quote
        nothing
    end)

    res

end

# Guard against declaring conflicts between sub/super components.
function vertical_conflict(err)
    (sub, sup) -> begin
        it = sub === sup ? "itself" : "its own super-component $sup"
        err("Component $sub cannot conflict with $it.")
    end
end

# Declare one particular conflict with a reason.
# Guard against redundant reasons specifications.
function declare_conflict(A::CompType, B::CompType, reason::Reason, err)
    vertical_guard(A, B, vertical_conflict(err))
    for (k, c, reason) in all_conflicts(A)
        isnothing(reason) && continue
        if B <: c
            as_K = k === A ? "" : " (as $k)"
            as_C = B === c ? "" : " (as $c)"
            err("Component $A$as_K already declared to conflict with $B$as_C \
                 for the following reason:\n  $(reason)")
        end
    end
    # Append new method or override by updating value.
    current = conflicts_(A) # Creates a new empty value if falling back on default impl.
    if isempty(current)
        # Dynamically add method to lend reference to the value lended by `conflicts_`.
        eval(quote
            conflicts_(::Type{$A}) = $current
        end)
    end
    current[B] = reason
end

# Fill up a clique, not overriding any existing reason.
function declare_conflicts_clique(err, components::Vector{<:CompType{V}}) where {V}

    # The result of overriding methods like the above
    # will not be visible from within the same function call
    # because of <mumblemumblejuliaworldcount>.
    # So, collect all required overrides in this collection
    # to perform them only once at the end.

    changes = Dict{CompType{V},Tuple{Bool,Any}}() # {Component: (needs_override, NewConflictsDict)}

    function process_pair(A::CompType{V}, B::CompType{V})
        vertical_guard(A, B, vertical_conflict(err))
        current = if haskey(changes, A)
            _, current = changes[A]
            current
        else
            current = conflicts_(A)
            changes[A] = (isempty(current), current)
            current
        end
        haskey(current, B) || (current[B] = nothing)
    end

    # Triangular-iterate to guard against redundant items.
    for (i, a) in enumerate(components)
        for b in components[1:(i-1)]
            process_pair(a, b)
            process_pair(b, a)
        end
    end

    # Perform all the overrides at once.
    for (C, (needs_override, conflicts)) in changes
        if needs_override
            eval(quote
                conflicts_(::Type{$C}) = $conflicts
            end)
        end
    end

end
