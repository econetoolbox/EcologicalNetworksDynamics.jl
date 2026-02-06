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
    mod = __module__
    src, input = Meta.quot.((__source__, input))
    quote
        $conflicts_macro($mod, $src, $input)
        nothing
    end
end
export @conflicts

function conflicts_macro(mod, src, input)

    # Raise on failure.
    err(mess) = throw(ConflictMacroError(src, mess))

    mod, input = parse_module(mod, input...)

    # Convenience local wrap.
    ceval(xp, ctx, type) = checked_eval(mod, xp, ctx, err, type)

    ValueType = Ref{Union{Nothing,DataType}}(nothing) # Refine later.
    evalcomp(xp, ctx) = eval_component(mod, xp, ValueType[], ctx, err)
    evalcomp_novaluetype(xp, ctx) = eval_component(mod, xp, ctx, err)

    #---------------------------------------------------------------------------------------
    # Parse and check macro input,

    length(input) == 0 && err("No macro arguments provided. \
                               Example usage:\n\
                               |  @conflicts(A, B, ..)\n\
                               ")


    # Infer the underlying system value type from the first argument.
    first_entry = nothing
    entries = []
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
        isnothing(invalid) || err("Not a list of conflict reasons: $(repr(invalid)).")
        isnothing(reasons) && (reasons = [])

        C = if isnothing(first_entry)
            ctx = "First conflicting entry"
            First = evalcomp_novaluetype(comp, ctx)
            ValueType[] = system_value_type(First)
            first_entry = comp # (save expression for later error message)
            First
        else
            evalcomp(comp, "Conflicting entry")
        end

        reasons = map(reasons) do reason
            @capture(reason, (conf_ => mess_))
            isnothing(conf) &&
                err("Not a `Component => \"reason\"` pair: $(repr(reason)).")
            conf = evalcomp(conf, "Reason reference")
            mess = ceval(mess, "Reason message", String)
            (conf, mess)
        end

        push!(entries, (C, reasons))

    end
    ValueType = ValueType[]

    length(entries) == 1 &&
        err("At least two components are required to declare a conflict \
             not only $(repr(first_entry)).")

    #---------------------------------------------------------------------------------------
    # Declare all conflicts, checking that provided reasons do refer to listed conflicts.
    comps = CompType{ValueType}[first(e) for e in entries]
    keys = OrderedSet{CompType{ValueType}}(comps)
    for (a, reasons) in entries
        for (b, message) in reasons
            b in keys || err("Conflict reason does not refer to a component listed \
                              in the same @conflicts invocation: $b => $(repr(message)).")
            declare_conflict(a, b, message, err)
        end
    end
    declare_conflicts_clique(err, comps)

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
    current = invokelatest() do
        conflicts_(A) # Creates a new empty value if falling back on default impl.
    end
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
            current = invokelatest(() -> conflicts_(A))
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
