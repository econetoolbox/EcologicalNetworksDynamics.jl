"""
Specify a set of conflicting components,
and optionally some of the reasons they conflict.

Full use:

```jl
define_conflicts(
    A => (B => "reason", C => "reason"),
    B => (A => "reason", C => "reason'),
    C => (A => "reason", B => "reason"),
)
```

Only the keys are required, and any reason can be omitted:

```jl
define_conflicts(
    A,
    B => (C => "reason"),
    C,
)
```

Minimal use: @conflicts(A, B, C)
"""

function define_conflicts(input...)

    err(mess) = throw(ConflictError(mess))

    #---------------------------------------------------------------------------------------
    # Input checks.

    V = nothing # Inferred from first read.

    entries = []
    for (i, entry) in enumerate(input)
        comp, reasons = try
            a, b = entry
            a, b
        catch _
            entry, []
        end

        if isempty(entries)
            C = check_component(comp, "First conflicting entry", err)
            V = system_value_type(C)
        else
            C = check_component(comp, V, "Conflicting entry [$i]", err)
        end

        reasons = map(enumerate(reasons)) do (j, reason)
            conf, mess = try
                a, b = reason
                a, b
            catch _
                (reason, nothing)
            end
            Conf = check_component(conf, V, "Reason reference [$i, $j]", err)
            isnothing(mess) || check_type(mess, "Reason message [$i, $j]", err, String)
            (Conf, mess)
        end

        push!(entries, (C, reasons))
    end

    length(entries) == 1 &&
        err("At least two components are required to declare a conflict \
            not only $(repr(first(first(entries)))).")

    #---------------------------------------------------------------------------------------
    # Declare all conflicts, checking that provided reasons do refer to listed conflicts.
    comps = CompType{V}[first(e) for e in entries]
    keys = OrderedSet{CompType{V}}(comps)
    for (i, (a, reasons)) in enumerate(entries)
        for (j, (b, message)) in enumerate(reasons)
            b in keys || err("Conflict reason [$i, $j] \
                              does not refer to a component listed \
                              in the same `define_conflicts()` call: \
                              $b => $(repr(message)).")
            declare_conflict(a, b, message, err)
        end
    end
    declare_conflicts_clique(err, comps)

end
export define_conflicts

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
