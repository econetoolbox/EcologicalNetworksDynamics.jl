# Add components to the system: check and expand.
#
# The expansion procedure is rather general,
# as it assumes that several blueprints are added at once
# and that they constitute an ordered *forest*
# since they each may imply "sub-blueprints".
#
# In addition, the caller can provide:
#   - `defaults`: a set of blueprints to be automatically added
#      if not explicitly provided as the main input.
#   - `hooks`: a set of blueprints to be automatically added
#      if either defaults or given blueprints require it.
#   - `excluded/without`: a set of components to explicitly not pick
#      from the defaults or the hooks.
#
# The challenge here is to correctly check for conflicts/inconsistencies etc.
# and then pick a correct expansion order.
# Here is the general procedure without additional options:
#   - The forest is visited pre-order to collect the corresponding graph of sub-blueprints:
#     the ones given by the caller are root nodes.
#     - Ignore implied blueprints for components already in the system.
#     - Build implied blueprints if they are not going to be added.
#     - Ignore implied blueprints if they are going to be added.
#     - Error if any implied component is already implied by another blueprint
#       and the two blueprints differ.
#     - Error if any required components was supposed to be excluded.
#   - When collection is over, decide whether to construct the defaults blueprints
#     and append them at the end of the forest.
#     Do this in pre-order again like an extension of the above step.
#   - Second traversal: visit the forest post-order to:
#     - Error if any implied component conflicts with components already in the system.
#     - Check requirements/conflicts against components already implied in pre-order.
#     - Trigger any required 'hook' by appending them to the forest (pre-order)
#       if this can avoid a 'MissingRequiredComponent' error.
#     - Run the `early_check`.
#     - Record requirements to determine the expansion order.
#   - Consume the forest from requirements to dependents to:
#     - Run the late `check`.
#     - Expand the blueprint into a component.
#     - Execute possible triggers.

# Prepare thorough analysis of recursive sub-blueprints possibly implied
# by the blueprints received.
# Reify the underlying 'forest' structure.
struct Node
    blueprint::Blueprint # Owned copy, so it doesn't leave refs to add! caller.
    parent::Option{Node}
    children::Vector{Node}
end

# Internal state of the add! procedure.
const Requirements{V} = OrderedSet{CompType{V}}
struct AddState{V}
    target::System{V}
    forest::Vector{Node}

    # Keep track of all blueprints about to be brought,
    # indexed by the concrete components they provide.
    # Blueprints providing several components are duplicated.
    # Populated during pre-order traversal.
    brought::Dict{CompType{V},Vector{Node}}

    # Keep track of the fully checked blueprints,
    # along with the implied blueprints that need to be expanded *prior* to them,
    # and the arbitrary data created by `early_check`.
    # Populated during post-order traversal.
    checked::OrderedDict{CompType{V},Tuple{Node,Requirements{V},Any}}

    # Defaults to be picked from.
    # The callables signature is (caller_status, if_unbrought) -> Blueprint:
    #  - `caller_status`: any value constructed after first pass
    #    from the `defaults_status(is_brought)` function provided by caller.
    #    where `is_brought` is a callable we provide to check whether
    #    the given component is found to be about to be added after the first forest visit.
    #  - `if_unbrought(C, BP)` is a callable we provide to fill default sub-blueprints.
    #    It either returns nothing if C is already brought
    #    or it calls the caller-provided constructor `BP`.
    defaults::OrderedDict{CompType{V},Function}

    # Pick blueprints from the hooks if possible to avoid MissingRequiredComponent.
    hooks::Dict{CompType{V},Blueprint{V}}

    # List components that the caller wishes to not automatically add.
    excluded::Vector{CompType{V}}

    AddState{V}(target::System{V}) where {V} =
        new(target, [], Dict(), OrderedDict(), OrderedDict(), Dict(), [])
end
is_excluded(add::AddState, c::CompRef) = any(X <: component_type(c) for X in add.excluded)
is_brought(add::AddState, c::CompRef) =
    any(B <: component_type(c) for B in keys(add.brought))

#-------------------------------------------------------------------------------------------
# Recursively create during first pass, pre-order,
# possibly checking the indexed list of nodes already brought.
function Node(blueprint::Blueprint, parent::Option{Node}, system::System, add::AddState)
    (; brought) = add

    # Create node and connect to parent, without its children yet.
    node = Node(blueprint, parent, [])

    for C in componentsof(blueprint)
        isabstracttype(C) &&
            throw(InternalAddError("No blueprint expands into an abstract component."))

        is_excluded(add, C) && throw(ExcludedBrought(C, node))

        # Check for duplication.
        implied = !isnothing(parent)
        !implied && has_component(system, C) && throw(BroughtAlreadyInValue(C, node))

        # Check for consistency with other possible blueprints bringing the same component.
        if haskey(brought, C)
            others = brought[C]
            for other in others
                blueprint == other.blueprint ||
                    throw(InconsistentForSameComponent(C, node, other))
            end
            push!(others, node)
        else
            brought[C] = [node]
        end
    end

    # Recursively construct children.
    B = typeof(blueprint)
    comperr(m) = throw(ComponentError(m))
    report(v) = ": $(repr(v)) ::$(typeof(v))."
    implied = F.implied(blueprint)
    applicable(iterate, implied) ||
        comperr("Not an iterable list of component types$(report(implied))")
    for C in implied
        C isa Component && (C = typeof(C)) # (accepting component instances)
        C isa CompType || comperr("Not a component type$(report(C))")
        eV = system_value_type(system)
        aV = system_value_type(C)
        eV === aV || comperr("Blueprint $(bc(B)) for values of `$eV` is \
                             implying component $(cc(C)) for values of `$aV`.")
        implies_blueprint_for(blueprint, C) || comperr(
            "Blueprint $(bc(B)) is supposed to imply $(cc(C)) \
             but the corresponding method is not defined: $F.$implied_blueprint_for.",
        )
        # Skip it if already brought or already present in the target system.
        has_component(system, C) && continue
        is_brought(add, C) && continue
        bp = implied_blueprint_for(blueprint, C)
        bp isa Blueprint ||
            comperr("Implicit constructor to implying $(cc(C)) from $(bc(B)) \
                     did not yield a blueprint but$(report(bp))")
        comps = componentsof(bp)
        any(comp -> comp <: C, comps) || comperr("Blueprint $(bc(typeof(blueprint))) \
                                                  is supposed to imply a blueprint \
                                                  for $(cc(C)), \
                                                  but it implied a blueprint for \
                                                  [$(join(map(cc, collect(comps)), ","))] \
                                                  instead.")
        child = Node(bp, node, system, add)
        push!(node.children, child)
    end

    node
end

#-------------------------------------------------------------------------------------------
# Recursively check during second pass, post-order,
# assuming the whole tree is set up (hooks aside).
function check!(add::AddState, node::Node)

    (; target, checked, hooks) = add

    # Recursively check children first.
    for child in node.children
        check!(add, child)
    end

    # Check requirements.
    blueprint = node.blueprint
    reqs = []
    for C in componentsof(blueprint)
        for (R, reason) in requires(C)
            push!(reqs, (R, reason, C))
        end
    end
    for (R, reason) in checked_expands_from(blueprint)
        push!(reqs, (R, reason, nothing))
    end
    for (R, reason, requirer) in reqs
        # Check against the current system value.
        has_component(target, R) && continue
        # Check against other components about to be provided.
        if !is_brought(add, R)
            # No blueprint brings the missing component.
            # Pick it from the hooks if to fill up the gap if any.
            hooked = false
            for H in keys(hooks)
                if H <: R
                    # Append the hook to the forest,
                    # re-doing the first pass over it at least.
                    hook = pop!(hooks, H)
                    root = Node(hook, nothing, false, target, add)
                    push!(add.forest, root)
                    hooked = true
                    break
                end
            end
            hooked || throw(MissingRequiredComponent(R, requirer, node, reason))
        end
    end

    # Guard against conflicts.
    for C in componentsof(blueprint)
        for (C_as, Other, reason) in all_conflicts(C)
            if has_component(target, Other)
                (Other, OtherAbstract) =
                    isabstracttype(Other) ? (first(abstract(target)[Other]), Other) :
                    (Other, nothing)
                throw(
                    ConflictWithSystemComponent(
                        C,
                        C_as === C ? nothing : C_as,
                        node,
                        Other,
                        OtherAbstract,
                        reason,
                    ),
                )
            end
            for Chk in keys(checked)
                if Chk <: Other
                    n, _ = checked[Chk]
                    throw(
                        ConflictWithBroughtComponent(
                            C,
                            C_as === C ? nothing : C_as,
                            node,
                            Chk,
                            Chk === Other ? nothing : Other,
                            n,
                            reason,
                        ),
                    )
                end
            end
        end

        # Run exposed hook for further checking.
        data = try
            early_check(blueprint)
        catch e
            if e isa InputError
                rethrow(HookCheckFailure(node, message(e), false))
            else
                throw(UnexpectedHookFailure(node, false))
            end
        end

        # Record as a fully checked node, along with the list of nodes
        # to expand prior to itself.
        checked[C] =
            (node, OrderedSet(R for (R, _, _) in reqs if !has_component(target, R)), data)
    end

end

# ==========================================================================================
# Entry point into adding components from a forest of blueprints.
function add!(
    system::System{V},
    blueprints::Union{Blueprint{V},BlueprintSum{V}}...;
    # (see the documentation for `AddState` to understand the following options)
    defaults_status = (_) -> (),
    defaults = [],
    hooks = Blueprint{V}[],
    without = [],
) where {V}

    # Construct internal state.
    add = AddState{V}(system)

    isacomponent(without) && (without = [without]) # (interpret single as singleton)
    for w in without
        isacomponent(w) || argerr("Not a component: $(repr(w)) ::$(typeof(w)).")
        push!(add.excluded, component_type(w))
    end

    # Extract blueprints from their sums.
    bps = []
    for bp in blueprints
        terms = bp isa BlueprintSum ? bp.pack : (bp,)
        for bp in terms
            push!(bps, bp)
        end
    end
    blueprints = bps

    for h in hooks
        for H in componentsof(h)
            H in add.excluded && continue
            add.hooks[H] = h
        end
    end

    (; forest, brought, checked) = add
    #---------------------------------------------------------------------------------------
    # Read-only preliminary checking.

    # Preorder visit: construct the trees.
    for bp in blueprints
        root = Node(bp, nothing, system, add)
        push!(forest, root)
    end

    # Construct caller state,
    # useful for them to decide their defaults
    # depending on the blueprints already brought.
    is_brought_(C) = is_brought(add, component_type(C))
    caller_state = defaults_status(is_brought_)
    # Based on this state,
    # ask the caller to construct their additional default blueprints.
    if_unbrought(U, BP) = is_brought_(component_type(U)) ? nothing : BP()
    for (D, build_default) in defaults
        D = component_type(D)
        is_excluded(add, D) && continue
        is_brought_(D) && continue
        def = build_default(caller_state, if_unbrought)
        root = Node(def, nothing, false, system, add)
        push!(forest, root)
    end

    # Post-order visit, check requirements, using hooks if needed.
    for node in forest
        check!(add, node)
    end

    #---------------------------------------------------------------------------------------
    # Secondary checking, occuring while the system is being modified.

    try

        # Construct a copy all possible triggers,
        # pruned from components already in-place.
        # Triggers execute whenever a newly added component
        # makes one of them empty.
        # TODO: should this sophisticated 'decreasing counter'
        # rather belong to the system itself?
        # Pros: alleviate calculations during `add!`
        # Cons: clutters `System` fields instead:
        #       every system would starts 'full' with all potential future triggers.
        triggers = OrderedDict()
        current_components = Set()
        for C in component_types(system)
            push!(current_components, C)
            for sup in supertypes(C)
                push!(current_components, sup)
            end
        end
        for (combination, fns) in triggers_(V)
            consumed = setdiff(combination, current_components)
            isempty(consumed) && continue
            triggers[combination] = (consumed, fns)
        end

        # Order the checked blueprints so their requirements are met prior to expansion.
        expand = OrderedDict{CompType{V},Any}()
        while !isempty(checked)
            # Search for the first component
            # whose bringer blueprint has all requirements met.
            (C, (_, reqs, data)) = first(checked)
            while true
                for R in reqs
                    haskey(expand, R) && continue
                    C = R
                    _, reqs, data = checked[R]
                    break
                end
                break
            end
            # Expand it before the others.
            pop!(checked, C)
            expand[C] = data
        end

        # Expand them all in correct order.
        for (C, data) in expand
            node = first(brought[C])
            blueprint = node.blueprint

            # Last check hook against current system value.
            data = try
                late_check(system, blueprint, data)
            catch e
                if e isa InputError
                    rethrow(HookCheckFailure(node, message(e), true))
                else
                    throw(UnexpectedHookFailure(node, true))
                end
            end

            # Expand.
            try
                expand!(system, blueprint, data)
            catch _
                throw(ExpansionAborted(node))
            end

            # Record.
            just_added = Set()
            for C in componentsof(blueprint)
                crt, abs = concrete(system), abstract(system)
                push!(crt, C)
                push!(just_added, C)
                for sup in supertypes(C)
                    sup === C && continue
                    sup === Component{V} && break
                    sub = haskey(abs, sup) ? abs[sup] : (abs[sup] = Set{CompType{V}}())
                    push!(sub, C)
                    push!(just_added, C)
                end
            end

            # Execute possible triggers.
            for (combination, (remaining, trigs)) in triggers
                setdiff!(remaining, just_added)
                if isempty(remaining)
                    for trig in trigs
                        try
                            trig(value(system), system)
                        catch _
                            throw(TriggerAborted(node, combination))
                        end
                    end
                    pop!(triggers, combination)
                end
            end


        end

    catch e
        # At this point, the system *has been modified*
        # but we cannot guarantee that all desired blueprints
        # have been expanded as expected.

        # These originated from hook in late check:
        # not all blueprints have been expanded,
        # but the underlying system state consistency is safe.
        e isa HookCheckFailure && rethrow(e)
        e isa UnexpectedHookFailure && rethrow(e)
        # This is unexpected and it may have occured during expansion.
        # The underlying system state consistency is no longuer guaranteed.
        raise = if e isa ExpansionAborted
            title = "Failure during blueprint expansion."
            subtitle = "This is a bug in the components library."
            who = "component authors"
            epilog = render_path(e.node)
            rethrow
        elseif e isa TriggerAborted
            title = "Failure during trigger execution \
                     for the combination of components \
                     {$(join(sort(collect(e.combination); by=T->T.name.name), ", "))}."
            subtitle = "This is a bug in the components library."
            who = "component authors"
            epilog = render_path(e.node)
            rethrow
        else
            title = "Failure during blueprint addition."
            subtitle = "This is a bug in the internal addition procedure."
            who = "package developers"
            epilog = ""
            throw
        end
        raise(ErrorException("\n$(crayon"red")\
               ⚠ ⚠ ⚠ $title ⚠ ⚠ ⚠\
               $reset\n\
               $subtitle\n\
               This system state consistency \
               is no longer guaranteed by the program. \
               This should not have happened.\n\
               Consider reporting to $who if you can reproduce \
               with a minimal example.\n\
               In any case, please drop the current system value \
               and create a new one.\n\
               $epilog"))
    end

    system

end
export add!

# ==========================================================================================
# Dedicated exceptions.
# Bundle information necessary for abortion on failure
# and displaying of a useful message,
# provided the tree will still be consistenly readable.

abstract type AddError <: SystemException end

# ==========================================================================================
# Ease exception testing by comparing blueprint paths along tree to simple vectors.
# The vector starts from current node,
# and expands up to a sequence of blueprint types and flags:
const PathElement = Type{<:Blueprint}
const BpPath = Vector{PathElement}

compreport = "\nThis is a bug in the component library. \
              Please report to component authors \
              if you can reproduce with a minimal example."

frareport = "\nThis is a bug in the framework. \
             Please report to package authors \
             if you can reproduce with a minimal example."

# Extract path from Node.
function path(node::Node)::BpPath
    res = PathElement[typeof(node.blueprint)]
    while !isnothing(node.parent)
        node = node.parent
        push!(res, typeof(node.blueprint))
    end
    res
end

# Render errors into proper error messages.
function render_path(path::BpPath; prefix = true)
    p1 = stripped_path(path[1])
    res = prefix ? "$(gray)in$reset " : ""
    res *= "$blueprint_color$p1$reset\n"
    for parent in path[2:end]
        parent = stripped_path(parent)
        res *= "$gray implied by:$reset $blueprint_color$parent$reset\n"
    end
    res
end
render_path(node::Node; kwargs...) = render_path(path(node); kwargs...)

struct BroughtAlreadyInValue <: AddError
    Comp::CompType
    node::Node
end
function Base.showerror(io::IO, e::BroughtAlreadyInValue)
    (; Comp, node) = e
    path = render_path(node)
    print(
        io,
        "Blueprint would expand into component $(cc(Comp)), \
         which is already in the system.\n$path",
    )
end

struct ExcludedBrought <: AddError
    Comp::CompType
    node::Node
end
function Base.showerror(io::IO, e::ExcludedBrought)
    (; Comp, node) = e
    path = render_path(node)
    print(
        io,
        "Component $(cc(Comp)) is explicitly excluded \
         but this blueprint is bringing it:\n$path",
    )
end

struct InconsistentForSameComponent <: AddError
    Comp::CompType
    focal::Node
    other::Node
end
function Base.showerror(io::IO, e::InconsistentForSameComponent)
    (; focal, other) = e
    println(io, "Component would be brought by two inconsistent blueprints:")
    Base.show(io, MIME("text/plain"), focal.blueprint)
    println(io, '\n' * render_path(focal))
    println(io, "  * OR *\n")
    Base.show(io, MIME("text/plain"), other.blueprint)
    println(io, '\n' * render_path(other))
end

struct MissingRequiredComponent <: AddError
    Miss::CompType
    Comp::Option{CompType} # Set if the *component* requires, none if the *blueprint* does.
    node::Node
    reason::Reason
end
function Base.showerror(io::IO, e::MissingRequiredComponent)
    (; Miss, Comp, node, reason) = e
    path = render_path(node)
    if isnothing(Comp)
        header = "Blueprint cannot expand without component $(cc(Miss))"
    else
        header = "Component $(cc(Comp)) requires $(cc(Miss)), neither found in the system \
                  nor brought by the blueprints"
    end
    if isnothing(reason)
        body = "."
    else
        it = crayon"italics"
        body = ":\n  $it$reason$reset"
    end
    print(io, "$header$body\n$path")
end

late_fail_warn(path) = "Not all blueprints have been expanded.\n\
                        This means that the system consistency is still guaranteed, \
                        but some components have not been added.\n\
                        $path"

struct HookCheckFailure <: AddError
    node::Node
    message::String
    late::Bool
end
function Base.showerror(io::IO, e::HookCheckFailure)
    (; node, message, late) = e
    path = render_path(node)
    if late
        header = "Blueprint cannot expand against current system value"
        footer = late_fail_warn(path)
    else
        header = "Blueprint value cannot be expanded"
        footer = path
    end
    it = crayon"italics"
    print(io, "$header:\n$it$message$reset\n$footer")
end

struct UnexpectedHookFailure <: AddError
    node::Node
    late::Bool
end
function Base.showerror(io::IO, e::UnexpectedHookFailure)
    (; node, late) = e
    path = render_path(node)
    if late
        header = "Unexpected failure during late blueprint checking."
        footer = late_fail_warn(path)
    else
        header = "Unexpected failure during early blueprint checking."
        footer = path
    end
    print(io, "$header$compreport\n$footer")
end

struct ConflictWithSystemComponent <: AddError
    Comp::CompType
    CompAbstract::Option{CompType} # Fill if 'comp' conflicts as this abstract type.
    node::Node
    Other::CompType
    OtherAbstract::Option{CompType} # Fill if 'other' conflicts as this abstract type.
    reason::Reason
end
function Base.showerror(io::IO, e::ConflictWithSystemComponent)
    (; Comp, CompAbstract, node, Other, OtherAbstract, reason) = e
    path = render_path(node)
    comp_as = isnothing(CompAbstract) ? "" : " (as a $(cc(CompAbstract)))"
    other_as = isnothing(OtherAbstract) ? "" : " (as a $(cc(OtherAbstract)))"
    header = "Blueprint would expand into $(cc(Comp)), \
              which$comp_as conflicts with $Other$other_as already in the system"
    if isnothing(reason)
        body = "."
    else
        body = ":\n  $reason"
    end
    print(io, "$header$body\n$path")
end

struct ConflictWithBroughtComponent <: AddError
    Comp::CompType
    CompAbstract::Option{CompType}
    node::Node
    Other::CompType
    OtherAbstract::Option{CompType}
    other_node::Node
    reason::Reason
end
function Base.showerror(io::IO, e::ConflictWithBroughtComponent)
    (; Comp, CompAbstract, node, Other, OtherAbstract, other_node, reason) = e
    path = render_path(node)
    other_path = render_path(other_node; prefix = false)
    comp_as = isnothing(CompAbstract) ? "" : " (as a $(cc(CompAbstract)))"
    other_as = isnothing(OtherAbstract) ? "" : " (as a $(cc(OtherAbstract)))"
    header = "Blueprint would expand into $(cc(Comp)), \
              which$comp_as would conflict with $(cc(Other))$other_as \
              already brought by the same blueprint"
    if isnothing(reason)
        body = "."
    else
        body = ":\n  $reason"
    end
    print(io, "$header$body\nAlready brought: $other_path---\n$path")
end

struct InternalAddError <: AddError
    mess::String
end
function Base.showerror(io::IO, e::InternalAddError)
    (; mess) = e
    print(io, mess)
    print(io, frareport)
end

struct ComponentError <: AddError
    mess::String
end
function Base.showerror(io::IO, e::ComponentError)
    (; mess) = e
    print(io, mess)
    print(io, compreport)
end

struct ExpansionAborted <: AddError
    node::Node
end

struct TriggerAborted <: AddError
    node::Node
    combination::Set
end
