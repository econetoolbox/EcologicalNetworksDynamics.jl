# Add components to the system: check and expand.
#
# Here is the add!(system, blueprint) procedure for one focal blueprint:
#   - The given blueprint is visited pre-order
#     to collect the corresponding graph of sub-blueprints:
#     it is the root node, and edges are colored depending on whether
#     the brought is an 'embedding' or an 'implication'.
#     - Error if an embedded blueprint brings a component already in the system.
#     - Ignore implied blueprints bringing components already in the system.
#     - Error if any brought component is already brought by another sub-blueprint
#       and the two differ.
#     - Error if any brought component conflicts with components already in the system.
#   - When collection is over, visit the tree post-order to:
#     - Check requirements/conflicts against components already brought in pre-order.
#     - Run the `early_check`.
#   - Visit post-order again to:
#     - Run the late `check`.
#     - Expand the blueprint into a component.
#     - Execute possible triggers.
#
# TODO: Exposing the first analysis steps of the above will be useful
# to implement default_model.
# The default model handles a *forest* of blueprints, and needs to possibly *move* nodes
# from later blueprints to earlier blueprints so as to make the inference intuitive and
# consistent.
# Maybe this can even be implemented within the framework itself, something along:
#    add_default!(
#        forest::Blueprints;
#        without = Component[],
#        defaults = OrderedDict{Component,Function{<SomeState> ↦ Blueprint}}(),
#        state_control! = Function{new_brought/implied_blueprint ↦ edit_state},
#    )

# Prepare thorough analysis of recursive sub-blueprints possibly brought
# by the blueprints given.
# Reify the underlying 'forest' structure.
struct Node
    blueprint::Blueprint # Owned copy, so it doesn't leave refs to add! caller.
    parent::Option{Node}
    implied::Bool # Raise if 'implied' by the parent and not 'embedded'.
    children::Vector{Node}
end

# Keep track of the blueprints about to be brought,
# indexed by the concrete components they provide.
# Blueprints providing several components are duplicated.
const BroughtList{V} = Dict{CompType{V},Vector{Node}}

#-------------------------------------------------------------------------------------------
# Recursively create during first pass, pre-order,
# possibly checking the indexed list of nodes already brought.
function Node(
    blueprint::Blueprint,
    parent::Option{Node},
    implied::Bool,
    system::System,
    brought::BroughtList,
)

    # Create node and connect to parent, without its children yet.
    node = Node(blueprint, parent, implied, [])

    for C in componentsof(blueprint)
        isabstracttype(C) && throw("No blueprint expands into an abstract component. \
                                    This is a bug in the framework.")

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
            has_component(system, implied_C) && continue
            implied_bp = try
                checked_implied_blueprint_for(blueprint, implied_C)
            catch e
                e isa _CannotImplyConstruct && throw(CannotImplyConstruct(implied_C, node))
                rethrow(e)
            end
            child = Node(implied_bp, node, true, system, brought)
            push!(node.children, child)
        elseif br isa Blueprint
            # An 'embedded' blueprint is brought.
            embedded_bp = br
            child = Node(embedded_bp, node, false, system, brought)
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
# assuming the whole tree is set up.
function check(
    node::Node,
    system::System,
    brought::BroughtList,
    checked::OrderedDict{<:CompType,Node},
)

    # Recursively check children first.
    for child in node.children
        check(child, system, brought, checked)
    end

    # Check requirements.
    blueprint = node.blueprint
    for C in componentsof(blueprint)
        for (reqs, requirer) in
            [(requires(C), C), (checked_expands_from(blueprint), nothing)]
            for (R, reason) in reqs
                # Check against the current system value.
                has_component(system, R) && continue
                # Check against other components about to be brought.
                any(C -> R <: C, keys(checked)) ||
                    throw(MissingRequiredComponent(R, requirer, node, reason))
            end
        end

        # Guard against conflicts.
        for (C_as, Other, reason) in all_conflicts(C)
            if has_component(system, Other)
                (Other, Other_abstract) =
                    isabstracttype(Other) ? (first(system._abstract[Other]), Other) :
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
                    throw(
                        ConflictWithBroughtComponent(
                            C,
                            C_as === C ? nothing : C_as,
                            node,
                            Chk,
                            Chk === Other ? nothing : Other,
                            checked[Chk],
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

        checked[C] = node
    end

end

# ==========================================================================================
# Entry point into adding components from a forest of blueprints.
function add!(system::System{V}, blueprints::Blueprint{V}...) where {V}

    if length(blueprints) == 0
        argerr("No blueprint given to expand into the system.")
    end

    forest = Node[]
    brought = BroughtList{V}() # Populated during pre-order traversal.
    checked = OrderedDict{CompType{V},Node}() # Populated during first post-order traversal.

    #---------------------------------------------------------------------------------------
    # Read-only preliminary checking.

    try

        # Preorder visit: construct the trees.
        for bp in blueprints
            # Get our owned local copy so it cannot be changed afterwards by the caller.
            bp = copy(bp)
            root = Node(bp, nothing, false, system, brought)
            push!(forest, root)
        end

        # Post-order visit, check requirements.
        for node in forest
            check(node, system, brought, checked)
        end

    catch e
        # The system value has not been modified during if the error is caught now.
        E = typeof(e)
        if E in (
            BroughtAlreadyInValue,
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

        # Second post-order visit: expand the blueprints.
        for Chk in keys(checked)
            node = first(brought[Chk])
            blueprint = node.blueprint

            # Temporary patch after renaming check -> late_check
            # to forbid silent no-checks.
            applicable(check, system_value_type, blueprint) &&
                throw("The `check` method seems defined for $blueprint, \
                       but it wouldn't be run as the new name is `late_check`.")

            # Last check hook against current system value.
            try
                late_check(system._value, blueprint, system)
            catch e
                if e isa CheckError
                    rethrow(HookCheckFailure(node, e.message, true))
                else
                    throw(UnexpectedHookFailure(node, true))
                end
            end

            # Expand.
            try
                expand!(system._value, blueprint, system)
            catch _
                throw(ExpansionAborted(node))
            end

            # Record.
            just_added = Set()
            for C in componentsof(blueprint)
                crt, abs = system._concrete, system._abstract
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
                            trig(system._value, system)
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
                        The system consistency is still guaranteed, \
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
