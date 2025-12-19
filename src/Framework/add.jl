# Add components to the system: check and expand.
#
# The expansion procedure is rather general,
# as it assumes that several blueprints are added at once
# and that they constitute an ordered *forest*
# since they each may bring sub-blueprints.
#
# In addition, the caller can provide:
#   - `defaults`: a set of blueprints to be automatically added
#      if not explicitly provided as the main input.
#   - `hooks`: a set of sub-blueprints to be automatically brought
#      if either defaults or given blueprints require it.
#   - `excluded/without`: a set of components to explicitly *not* bring
#      from the defaults, or the hooks.
#
# The challenge here is to correctly check for conflicts/inconsistencies etc.
# and then pick a correct expansion order.
# Here is the general procedure without additional options:
#   - The forest is visited pre-order to collect the corresponding graph of sub-blueprints:
#     the ones given by the caller are root nodes,
#     and edges are colored depending on whether the 'broughts' are 'embedded' or 'implied'.
#     - Error if an embedded blueprint brings a component already in the system.
#     - Ignore implied blueprints bringing components already in the system.
#     - Build implied blueprints if they are not already brought.
#     - Ignore implied blueprints if they are already brought.
#     - Error if any brought component is already brought by another blueprint
#       and the two differ.
#     - Error if any brought components was supposed to be excluded.
#   - When collection is over, decide whether to construct the defaults blueprints
#     and append them at the end of the forest,
#     pre-order again like an extension of the above step.
#   - Second traversal: visit the forest post-order to:
#     - Error if any brought component conflicts with components already in the system.
#     - Check requirements/conflicts against components already brought in pre-order.
#     - Trigger any required 'hook' by appending them to the forest (pre-order)
#       if this can avoid a 'MissingRequiredComponent' error.
#     - Run the `early_check`.
#     - Record requirements to determine the expansion order.
#   - Consume the forest from requirements to dependents to:
#     - Run the late `check`.
#     - Expand the blueprint into a component.
#     - Execute possible triggers.

# Prepare thorough analysis of recursive sub-blueprints possibly brought
# by the blueprints given.
# Reify the underlying 'forest' structure.
struct Node
    blueprint::Blueprint # Owned copy, so it doesn't leave refs to add! caller.
    parent::Option{Node}
    implied::Bool # Raise if 'implied' by the parent and not 'embedded'.
    children::Vector{Node}
end

# Internal state of the add! procedure.
const Requirements{V} = OrderedSet{CompType{V}}
struct AddState{V}
    target::System{V}
    forest::Vector{Node}

    # Keep track of the blueprints about to be brought (including root blueprints),
    # indexed by the concrete components they provide.
    # Blueprints providing several components are duplicated.
    # Populated during pre-order traversal.
    brought::Dict{CompType{V},Vector{Node}}

    # Keep track of the fully checked blueprints,
    # along with the brought blueprints that need to be expanded *prior* to themselves.
    # Populated during post-order traversal.
    checked::OrderedDict{CompType{V},Tuple{Node,Requirements{V}}}

    # Bring defaults.
    # The callables signature is (caller_status, if_unbrought) -> Blueprint:
    #  - `caller_status`: any value constructed after first pass
    #    from the `defaults_status`(is_brought) function provided by caller.
    #    where `is_brought` is a callable we provide to check whether
    #    the given component is found to be brought after the first forest visit.
    #  - `if_unbrought(C, BP)` is a callable we provide to fill default sub-blueprints.
    #    It either returns nothing if C is already brought\
    #    or it calls the caller-provided constructor `BP`.
    defaults::OrderedDict{CompType{V},Function}

    # Pick blueprints from the hooks if possible to avoid MissingRequiredComponent.
    hooks::Dict{CompType{V},Blueprint{V}}

    # List components that the caller wishes to not automatically add.
    excluded::Vector{CompType{V}}

    AddState{V}(target::System{V}) where {V} =
        new(target, [], Dict(), OrderedDict(), OrderedDict(), Dict(), [])
end
is_excluded(add::AddState, C) = any(X <: C for X in add.excluded)
is_brought(add::AddState, C) = any(B <: C for B in keys(add.brought))

#-------------------------------------------------------------------------------------------
# Recursively create during first pass, pre-order,
# possibly checking the indexed list of nodes already brought.
function Node(
    blueprint::Blueprint,
    parent::Option{Node},
    implied::Bool,
    system::System,
    add::AddState,
)
    (; brought) = add

    # Create node and connect to parent, without its children yet.
    node = Node(blueprint, parent, implied, [])

    for C in componentsof(blueprint)
        isabstracttype(C) && throw("No blueprint expands into an abstract component. \
                                    This is a bug in the framework.")

        is_excluded(add, C) && throw(ExcludedBrought(C, node))

        # Check for duplication if embedded.
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
    for br in Framework.brought(blueprint)
        if br isa CompType
            # An 'implied' brought blueprint possibly needs to be constructed.
            implied_C = br
            # Skip it if already brought or already present in the target system.
            has_component(system, implied_C) && continue
            is_brought(add, implied_C) && continue
            implied_bp = try
                checked_implied_blueprint_for(blueprint, implied_C)
            catch e
                e isa _CannotImplyConstruct && throw(CannotImplyConstruct(implied_C, node))
                rethrow(e)
            end
            child = Node(implied_bp, node, true, system, add)
            push!(node.children, child)
        elseif br isa Blueprint
            # An 'embedded' blueprint is brought.
            embedded_bp = br
            child = Node(embedded_bp, node, false, system, add)
            push!(node.children, child)
        else
            throw("⚠ Invalid brought value. ⚠ \
                   This is either a bug in the framework or in the components library. \
                   Please report if you can reproduce with a minimal example.\n\
                   Received brought value: $br ::$(typeof(br)).")
        end
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
                (Other, Other_abstract) =
                    isabstracttype(Other) ? (first(abstract(target)[Other]), Other) :
                    (Other, nothing)
                throw(
                    ConflictWithSystemComponent(
                        C,
                        C_as === C ? nothing : C_as,
                        node,
                        Other,
                        Other_abstract,
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
        try
            early_check(blueprint)
        catch e
            if e isa CheckError
                rethrow(HookCheckFailure(node, e.message, false))
            else
                throw(UnexpectedHookFailure(node, false))
            end
        end

        # Record as a fully checked node, along with the list of nodes
        # to expand prior to itself.
        checked[C] =
            (node, OrderedSet(R for (R, _, _) in reqs if !has_component(target, R)))
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

    try

        # Preorder visit: construct the trees.
        for bp in blueprints
            root = Node(bp, nothing, false, system, add)
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

    catch e
        # The system value has not been modified during if the error is caught now.
        E = typeof(e)
        if E in (
            BroughtAlreadyInValue,
            ExcludedBrought,
            CannotImplyConstruct,
            InconsistentForSameComponent,
            MissingRequiredComponent,
            ConflictWithSystemComponent,
            ConflictWithBroughtComponent,
            HookCheckFailure,
        )
            rethrow(AddError(V, e))
        else
            rethrow(e)
        end
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
        expand = OrderedSet{CompType{V}}()
        while !isempty(checked)
            # Search for the first component
            # whose bringer blueprint has all requirements met.
            (C, (_, reqs)) = first(checked)
            while true
                for R in reqs
                    R in expand && continue
                    C = R
                    _, reqs = checked[R]
                    break
                end
                break
            end
            # Expand it before the others.
            pop!(checked, C)
            push!(expand, C)
        end

        # Expand them all in correct order.
        for C in expand
            node = first(brought[C])
            blueprint = node.blueprint

            # Last check hook against current system value.
            try
                late_check(value(system), blueprint, system)
            catch e
                if e isa CheckError
                    rethrow(HookCheckFailure(node, e.message, true))
                else
                    throw(UnexpectedHookFailure(node, true))
                end
            end

            # Expand.
            try
                expand!(value(system), blueprint, system)
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
        E = typeof(e)
        if E in (HookCheckFailure, UnexpectedHookFailure)
            # This originated from hook in late check:
            # not all blueprints have been expanded,
            # but the underlying system state consistency is safe.
            rethrow(AddError(V, e))
        else
            # This is unexpected and it may have occured during expansion.
            # The underlying system state consistency is no longuer guaranteed.
            raise = if e isa ExpansionAborted
                title = "Failure during blueprint expansion."
                subtitle = "This is a bug in the components library."
                epilog = render_path(e.node)
                rethrow
            elseif e isa TriggerAborted
                title = "Failure during trigger execution \
                         for the combination of components \
                         {$(join(sort(collect(e.combination); by=T->T.name.name), ", "))}."
                subtitle = "This is a bug in the components library."
                epilog = render_path(e.node)
                rethrow
            else
                title = "Failure during blueprint addition."
                subtitle = "This is a bug in the internal addition procedure."
                epilog = ""
                throw
            end
            raise(ErrorException("\n$(crayon"red")\
                   ⚠ ⚠ ⚠ $title ⚠ ⚠ ⚠\
                   $reset\n\
                   $subtitle\n\
                   This system state consistency \
                   is no longer guaranteed by the program. \
                   This should not happen and must be considered a bug.\n\
                   Consider reporting if you can reproduce \
                   with a minimal example.\n\
                   In any case, please drop the current system value \
                   and create a new one.\n\
                   $epilog"))
        end
    end

    system

end
export add!

# ==========================================================================================
# Dedicated exceptions.
# Bundle information necessary for abortion on failure
# and displaying of a useful message,
# provided the tree will still be consistenly readable.

abstract type AddException <: SystemException end

struct BroughtAlreadyInValue <: AddException
    comp::CompType
    node::Node
end

struct CannotImplyConstruct <: AddException
    comp::CompType
    node::Node
end

struct ExcludedBrought <: AddException
    comp::CompType
    node::Node
end

struct InconsistentForSameComponent <: AddException
    comp::CompType
    focal::Node
    other::Node
end

struct MissingRequiredComponent <: AddException
    miss::CompType
    comp::Option{CompType} # Set if the *component* requires, none if the *blueprint* does.
    node::Node
    reason::Reason
end

struct ConflictWithSystemComponent <: AddException
    comp::CompType
    comp_abstract::Option{CompType} # Fill if 'comp' conflicts as this abstract type.
    node::Node
    other::CompType
    other_abstract::Option{CompType} # Fill if 'other' conflicts as this abstract type.
    reason::Reason
end

struct ConflictWithBroughtComponent <: AddException
    comp::CompType
    comp_abstract::Option{CompType}
    node::Node
    other::CompType
    other_abstract::Option{CompType}
    other_node::Node
    reason::Reason
end

struct HookCheckFailure <: AddException
    node::Node
    message::String
    late::Bool
end

struct UnexpectedHookFailure <: AddException
    node::Node
    late::Bool
end

struct ExpansionAborted <: AddException
    node::Node
end

struct TriggerAborted <: AddException
    node::Node
    combination::Set
end

# Once the above have been processed,
# convert into this dedicated user-facing one:
struct AddError{V} <: SystemException
    e::AddException
    _::PhantomData{V}
    AddError(::Type{V}, e) where {V} = new{V}(e, PhantomData{V}())
end
Base.showerror(io::IO, e::AddError{V}) where {V} = showerror(io, e.e)

# ==========================================================================================
# Ease exception testing by comparing blueprint paths along tree to simple vectors.
# The vector starts from current node,
# and expands up to a sequence of blueprint types and flags:
#   true: implied
#   false: embedded
const PathElement = Union{Bool,Type{<:Blueprint}}
const BpPath = Vector{PathElement}

# Extract path from Node.
function path(node::Node)::BpPath
    res = PathElement[typeof(node.blueprint)]
    while !isnothing(node.parent)
        push!(res, node.implied)
        node = node.parent
        push!(res, typeof(node.blueprint))
    end
    res
end

# ==========================================================================================
# Render errors into proper error messages.

function render_path(path::BpPath)
    p1 = stripped_path(path[1])
    res = "$(grayed)in$reset $blueprint_color$p1$reset\n"
    i = 2
    while i <= length(path)
        broughtby = path[i] ? "     implied by:" : "embedded within:"
        parent = path[i+1]
        parent = stripped_path(parent)
        res *= "$grayed$broughtby$reset $blueprint_color$parent$reset\n"
        i += 2
    end
    res
end
render_path(node::Node) = render_path(path(node))

function Base.showerror(io::IO, e::BroughtAlreadyInValue)
    (; comp, node) = e
    path = render_path(node)
    print(
        io,
        "Blueprint would expand into component $(cc(comp)), \
         which is already in the system.\n$path",
    )
end

function Base.showerror(io::IO, e::CannotImplyConstruct)
    (; comp, node) = e
    path = render_path(node)
    print(
        io,
        "This particular brought $(cc(comp)) cannot be implicitly constructed.\n$path",
    )
end

function Base.showerror(io::IO, e::ExcludedBrought)
    (; comp, node) = e
    path = render_path(node)
    print(
        io,
        "Component $(cc(comp)) is explicitly excluded \
         but this blueprint is bringing it:\n$path",
    )
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

function Base.showerror(io::IO, e::MissingRequiredComponent)
    (; miss, comp, node, reason) = e
    path = render_path(node)
    if isnothing(comp)
        header = "Blueprint cannot expand without component $(cc(miss))"
    else
        header = "Component $(cc(comp)) requires $(cc(miss)), neither found in the system \
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
    print(io, "$header:\n  $it$message$reset\n$footer")
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
    print(
        io,
        "$header\n\
         This is a bug in the components library. \
         Please report if you can reproduce with a minimal example.\n\
         $footer",
    )
end

function Base.showerror(io::IO, e::ConflictWithSystemComponent)
    (; comp, comp_abstract, node, other, other_abstract, reason) = e
    path = render_path(node)
    comp_as = isnothing(comp_abstract) ? "" : " (as a $(cc(comp_abstract)))"
    other_as = isnothing(other_abstract) ? "" : " (as a $(cc(other_abstract)))"
    header = "Blueprint would expand into $(cc(comp)), \
              which$comp_as conflicts with $other$other_as already in the system"
    if isnothing(reason)
        body = "."
    else
        body = ":\n  $reason"
    end
    print(io, "$header$body\n$path")
end

function Base.showerror(io::IO, e::ConflictWithBroughtComponent)
    (; comp, comp_abstract, node, other, other_abstract, other_node, reason) = e
    path = render_path(node)
    other_path = render_path(other_node)
    comp_as = isnothing(comp_abstract) ? "" : " (as a $(cc(comp_abstract)))"
    other_as = isnothing(other_abstract) ? "" : " (as a $(cc(other_abstract)))"
    header = "Blueprint would expand into $(cc(comp)), \
              which$comp_as would conflict with $other$other_as \
              already brought by the same blueprint"
    if isnothing(reason)
        body = "."
    else
        body = ":\n  $reason"
    end
    print(io, "$header$body\nAlready brought: $other_path---\n$path")
end
