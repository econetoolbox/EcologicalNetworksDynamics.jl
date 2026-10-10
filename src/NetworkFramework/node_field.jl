# This abstracts over both subclass/sparse and root/dense fields,
# but any code easily moved to `subnode_field.jl` lives there.

"""
Raise to produce a 'Flat' blueprint
expanding the same scalar value to the whole class or web,
and allow flattening assignment.
If raised, provide the argument type for component-call constructor.
"""
flat(d::D.AbstractField) = D.type(d)
may_flat(d::D.AbstractField) = !isnothing(flat(d))

"Expand to a class field from a vector of raw values."
abstract type NodeFieldRawBlueprint <: Blueprint end

"Expand to a class field from mapped values."
abstract type NodeFieldMapBlueprint <: Blueprint end

"Expand to a class field from a single value."
abstract type NodeFieldFlatBlueprint <: Blueprint end

"Typical setup for a component bringing a new class field to the network."
function define_node_field_component(
    mod::Module,
    d::D.NodeField;
    blueprints = (), # Extra blueprints for the component.
    requires = (), # Extra requirements for the component.
)

    #---------------------------------------------------------------------------------------
    # Extract particular information for this (class, field) pair.
    _D = typeof(d)
    cl, _ = D.Class(d)
    Class = D.component(cl)
    _Class = typeof(Class)
    class, field = D.content(d)
    singular, plural, Singular, Plural, short = D.name_variants(d)
    T = D.type(d)

    # Use it to generate adequate code.
    Singular_ = Symbol(Singular, :_) # Blueprints module name.
    _Singular = Symbol(:_, Singular) # Component type name.

    # ======================================================================================
    # Blueprints for the component.

    # Prepare dedicated blueprints module and populate namespace.
    bpmod = mod.eval(
        (
            quote
                module $Singular_
                import EcologicalNetworksDynamics.NetworkFramework: F, NF, D, @bp_construct
                const d, T, Class = $d, $T, $Class
                end
            end
        ).args |> last,
    )

    #---------------------------------------------------------------------------------------
    # From raw values.

    bpmod.eval(
        quote
            mutable struct Raw <: NF.NodeFieldRawBlueprint
                $short::Vector{T}
                @bp_construct Raw
            end
            export Raw
            NF.data(b::Raw) = b.$short
            NF.register_blueprint(Raw, "raw values"; d,
                implied = (Class,), # Infer number of class nodes from vector size.
            )
        end,
    )

    #---------------------------------------------------------------------------------------
    # From a node-indexed map.

    bpmod.eval(
        quote
            mutable struct Map <: NF.NodeFieldMapBlueprint
                $short::NF.Map{T}
                @bp_construct Map
            end
            export Map
            NF.data(b::Map) = b.$short
            NF.register_blueprint(Map, $"[$class => $field] map"; d,
                implied = (Class,), # Infer class nodes from map keys.
            )
        end,
    )

    #---------------------------------------------------------------------------------------
    # From a scalar broadcasted to all nodes in the class (if meaningful).
    if may_flat(d)
        bpmod.eval(
            quote
                mutable struct Flat <: NF.NodeFieldFlatBlueprint
                    $short::T
                    @bp_construct Flat
                end
                export Flat
                NF.data(bp::Flat) = bp.$short
                NF.register_blueprint(Flat, "uniform value"; d, depends = (Class,))
            end,
        )
    end

    # ======================================================================================
    # The component itself and generic blueprints constructors.

    c = NF.eval(
        quote
            define_component(
                $(Meta.quot(Singular)),
                $mod;
                requires = ($Class, $(requires...)),
                blueprints = ($bpmod, $(blueprints...)),
            )
        end,
    )
    C = typeof(c)
    NF.eval(quote
        $D.component(::$_D) = $c
        (::$C)($short, args...) = $construct($d, $c, $short, args...)
    end)

    if may_flat(d)
        R = flat(d) # Receiver type.
        NF.eval(quote
            (::$C)($short::$R) = $c.Flat($short)
        end)
    end

    # Queries.
    M = Symbol(Plural, :_Methods)
    prop = [singular]
    mod.eval(
        (
            quote
                module $M
                using EcologicalNetworksDynamics.NetworkFramework: V, NF, D, Network, Model
                const d, prop, C = $d, $prop, $C
                D.viewtype(::typeof(d)) = V.NodeFieldView
                get_value(::Network, m::Model) = V.field_view(d, m)
                NF.define_method(get_value; read_as = prop, depends = (C,))
                if !D.readonly(d)
                    set_value!(::Network, m::Model, input) = NF.assign!(d, m, input)
                    NF.define_method(set_value!; write_as = prop, depends = (C,))
                end
                end
            end
        ).args |> last,
    )

    # Display.
    NF.eval(quote
        F.shortline(io::IO, model::Model, ::$C) = NF.nodes_shortline(io, model, $d)
    end)

    (c, C)
end

# ==========================================================================================
# Specialization.

datatype(B::Type{<:NodeFieldRawBlueprint}) = Vector{D.type(B)}
datatype(B::Type{<:NodeFieldMapBlueprint}) = Map{D.type(B)}
datatype(B::Type{<:NodeFieldFlatBlueprint}) = D.type(B)

#-------------------------------------------------------------------------------------------
# Construct.

# Allow passing values as separate arguments.
construct(B::Type{<:Union{NodeFieldRawBlueprint,NodeFieldMapBlueprint}},
    first, second, rest...) =
    @invoke construct(B::Type{<:Blueprint}, (first, second, rest...))

# ==========================================================================================
# ↑ ↑ HERE update impl ↑ ↑
# ==========================================================================================

#-------------------------------------------------------------------------------------------
# Check data values without model information, against the target type.

check(d::D.AbstractField, value) = NF.convert(D.type(d), value)

check_with_ref(d::D.AbstractNodeField, value, i::Int) =
    try
        check(d, value)
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "At node index [$i]")
    end
check_with_ref(d::D.AbstractNodeField, value, l::Symbol) =
    try
        check(d, value)
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "At node with label $(repr(l))")
    end

#-------------------------------------------------------------------------------------------
# Check against a model value, assuming the type and raw value is already correct.

# No check by default.
check(::D.AbstractField, ::Model, value) = value
# Contextualized.
check(d::D.AbstractField, m::Model, value, _index, _label) = check(d, m, value)

#-------------------------------------------------------------------------------------------
# Check against both the type and then immediately the model (useful for mutating).
# To this end, wrap the model in the following marker.
struct WholeCheck
    model::Model
end
get_model(w::WholeCheck) = w.model
get_model(m::Model) = m

function check(d::D.AbstractField, whole::WholeCheck, value)
    converted = check(d, value)
    check(d, whole.model, converted)
end

# Abstract over either whole check or just-model check.
function check_with_ref(d::D.AbstractNodeField, against::Model, value, i::Int, l::Symbol)
    try
        value = check(d, value)
        check(d, against, value, i, l)
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "At node with label $(repr(l)) ([$i])")
    end
end

# Use the model to automatically infer any reference type from the other one.
function check_with_ref(d::D.AbstractNodeField, against, value, i::Int)
    model = get_model(against)
    network = NF.network(model)
    class = D.class(d)
    index = N.index(network, class)
    l = N.to_label(index, i)
    check_with_ref(d, model, value, i, l)
end
function check_with_ref(d::D.AbstractNodeField, against, value, l::Symbol)
    model = get_model(against)
    network = NF.network(model)
    class = D.class(d)
    index = N.index(network, class)
    i = N.to_index(index, l)
    check_with_ref(d, model, value, i, l)
end

#-------------------------------------------------------------------------------------------
# Construct: any input is possible, but we don't know anything about the model yet.

function construct(d::D.AbstractNodeField, ::Type{<:NodeFieldRawBlueprint}, raw)
    T = D.type(d)
    try
        v = NF.convert(Vector{T}, raw)
        for (i, value) in enumerate(v)
            check_with_ref(d, value, i)
        end
        v
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "When constructing $d from raw values")
    end
end

function construct(d::D.AbstractNodeField, ::Type{<:NodeFieldMapBlueprint}, map)
    T = D.type(d)
    try
        out = NF.convert(Map{T}, map)
        for (l, v) in out
            check_with_ref(d, v, l)
        end
        out
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "When constructing $d from map")
    end
end

function construct(d::D.AbstractNodeField, ::Type{<:NodeFieldFlatBlueprint}, flat)
    T = D.type(d)
    try
        val = NF.convert(T, flat)
        check(d, val)
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "When constructing $d from a flat value")
    end
end

function construct(d::D.NodeField, Field::Component, input)
    parsed = parse(d, input)
    construct_from_parsed(d, Field, parsed)
end

construct_from_parsed(::D.NodeField, Field::Component, raw::Vector) = Field.Raw(raw)
construct_from_parsed(::D.NodeField, Field::Component, map::Map) = Field.Map(map)
construct_from_parsed(::D.NodeField, Field::Component, scalar) = Field.Flat(scalar)

"""
Pre-process whatever input into one of the three basic input types for this field.
"""
function parse(d::D.AbstractNodeField, input)
    T = D.type(d)
    tries = []
    if may_flat(d)
        push!(tries, T)
    end
    push!(tries, Vector{T})
    push!(tries, Map{T})
    try_convert(input, tries...)
end

#-------------------------------------------------------------------------------------------
# Early-check: correct type, unchecked values, no model information yet.

function early_check(d::D.AbstractField, bp::Blueprint)
    data = NF.data(bp)
    try
        early_check(d, data)
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "When checking $d blueprint data")
    end
end

function early_check(d::D.AbstractNodeField, vec::Vector)
    T = eltype(vec)
    data = T[]
    for (i, value) in enumerate(vec)
        value = check_with_ref(d, value, i)
        push!(data, value)
    end
    data
end

function early_check(d::D.AbstractNodeField, map::Map)
    T = valtype(map)
    map = NF.parse(Map{T}, map) # Re-parse in case the map was mutated.
    core_early_check(d, map)
end

# Assumes the input is a valid map.
function core_early_check(d::D.AbstractNodeField, map::Map)
    for (label, value) in map
        map[label] = check_with_ref(d, value, label)
    end
    map
end

#-------------------------------------------------------------------------------------------
# Late-check: correct type, checked values, model information is now available.

function late_check(d::D.AbstractField, model::Model, ::Blueprint, early_data)
    try
        late_check(d, model, early_data)
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "When checking $d blueprint against model")
    end
end

function late_check(d::D.AbstractNodeField, model::Model, vec::Vector)
    # Check number of values first.
    network = NF.network(model)
    class = D.class(d)
    n = N.n_nodes(network, class)
    l = length(vec)
    n == l || conserr("Wrong number of values received for $d: expected $n, got $l.")
    labels = N.node_labels(network, class)
    # Then check values one by one, with context to produce useful reports.
    map(enumerate(zip(labels, vec))) do (i, (label, value))
        check_with_ref(d, model, value, i, label)
    end
end

function late_check(d::D.AbstractNodeField, model::Model, map::Map{<:Any,Symbol})
    core_late_check(d, model, map)
    # Reorder values one by one into a vector.
    [check_with_ref(d, model, map[label], label) for label in keys(map)]
end

# Same with index references instead.
function late_check(d::D.AbstractNodeField, model::Model, map::Map{<:Any,Int})
    core_late_check(d, model, map)
    [check_with_ref(d, model, map[i], i) for i in eachindex(map)]
end

late_check(d::D.AbstractNodeField, model::Model, value) = check(d, model, value)

# Check without producing returned data.
function core_late_check(
    d::D.AbstractNodeField,
    model::Model,
    map::Map{<:Any,Symbol};
    must_be_complete = true, # Lower for assignment.
)
    # Check labels first.
    network = NF.network(model)
    class = D.class(d)
    labels = N.node_labels(network, class)
    exp = Set(labels)
    act = Set(keys(map))
    if must_be_complete
        miss = setdiff(exp, act)
        if !isempty(miss)
            miss = EN.join_elided(sort!(collect(miss)), ", ", " and ")
            conserr("Missing for $d, no value provided for $miss.")
        end
    end
    unexp = setdiff(act, exp)
    if !isempty(unexp)
        a, s = length(unexp) == 1 ? (" a", "") : ("", "s")
        unexp = EN.join_elided(sort!(collect(unexp)), ", ", " and ")
        conserr("Not$a $(repr(class)) name$s: $unexp.")
    end
    nothing
end

function core_late_check(
    d::D.AbstractNodeField,
    model::Model,
    map::Map{<:Any,Int};
    must_be_complete = true,
)
    # Check indices first.
    network = NF.network(model)
    class = D.class(d)
    n = N.n_nodes(network, class)
    miss = Int[]
    for exp in 1:n
        haskey(map, exp) && continue
        push!(miss, exp)
    end
    if must_be_complete && !isempty(miss)
        miss = EN.join_elided(miss, ", ", " and ")
        s = length(miss) == 1 ? "" : "s"
        conserr("Missing for $d, no value provided for node$s $miss.")
    end
    unexp = miss
    for act in keys(map)
        act in 1:n && continue
        push!(unexp, act)
    end
    if !isempty(unexp)
        unexp = EN.join_elided(unexp, ", ", " and ")
        indices, s = length(unexp) == 1 ? ("index", "") : ("indices", "s")
        conserr("Invalid $indices for class $(repr(class)) with $n node$s: $unexp.")
    end
    nothing
end

#-------------------------------------------------------------------------------------------
# Implied class blueprint.

function implied_class(::D.NodeField, Class, bp::NodeFieldRawBlueprint)
    raw = data(bp)
    n = length(raw)
    Class.Number(n)
end

implied_class(d::D.NodeField, Class, bp::NodeFieldMapBlueprint) =
    implied_class(d, Class, data(bp)) # Dispatch to either symbol or integer refs.

function implied_class(::D.NodeField, Class, map::Map{<:Any,Symbol})
    refs = NF.keys(map)
    Class.Names(collect(refs))
end

function implied_class(::D.NodeField, Class, map::Map{<:Any,Int})
    n = length(map) # (assuming no hole) TODO: how is that enforced?
    Class.Number(n)
end

#-------------------------------------------------------------------------------------------
# Expansion: input is completely trusted, just fill the inner network from late data.

expand!(
    d::D.AbstractNodeField,
    model::Model,
    # The two provide the same `late_data` after late checking.
    ::Union{NodeFieldRawBlueprint,NodeFieldMapBlueprint},
    late_data::Vector,
) = expand!(d, model, late_data)

# Special case flat-blueprint.
function expand!(d::D.AbstractNodeField, model::Model, ::NodeFieldFlatBlueprint, late_data)
    network = NF.network(model)
    class = D.class(d)
    n = N.n_nodes(network, class)
    vec = fill(late_data, n)
    expand!(d, model, vec)
end

function expand!(d::D.AbstractNodeField, model::Model, data::Vector)
    network = NF.network(model)
    (classname, fieldname) = D.content(d)
    class = N.class(network, classname)
    N.add_field!(class, fieldname, data)
end

#-------------------------------------------------------------------------------------------
# Mutation: called when setting through a view.
# Input may be anything,
# but the underlying model value and the reference can be assumed to be correct.

mutate_check(d::D.AbstractNodeField, model::Model, value, ref) =
    try
        check_with_ref(d, WholeCheck(model), value, ref)
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "When attempting to mutate $d node field")
    end

#-------------------------------------------------------------------------------------------
# Assignment: called when setting all values at once through a property.
# Input may be anything, but the underlying model value can be assumed to be correct.

assign!(d::D.AbstractNodeField, model::Model, input) =
    try
        assign_parsed!(d, model, parse(d, input))
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "When attempting to assign to $d node field")
    end

# Reassign all values from raw input.
function assign_parsed!(d::D.AbstractNodeField, model::Model, raw::Vector)
    early = early_check(d, raw)
    late = late_check(d, model, early)
    network = NF.network(model)
    (classname, fieldname) = D.content(d)
    class = N.class(network, classname)
    entry = class.data[fieldname]
    N.mutate!(entry) do nodes
        for (i, new_value) in enumerate(late)
            nodes[i] = new_value
        end
    end
end

# Reassign *some* values from mapped input.
function assign_parsed!(d::D.AbstractNodeField, model::Model, map::Map)
    core_early_check(d, map) # (avoids reparsing)
    core_late_check(d, model, map; must_be_complete = false) # Allow partial reassignment.
    network = NF.network(model)
    (classname, fieldname) = D.content(d)
    class = N.class(network, classname)
    entry = class.data[fieldname]
    index = class.index
    N.mutate!(entry) do nodes
        for (label, new_value) in map
            i = N.to_index(index, label)
            nodes[i] = new_value
        end
    end
end

# Assume the assignment input is a scalar to flatten to all nodes.
function assign_parsed!(d::D.AbstractNodeField, model::Model, input)
    network = NF.network(model)
    (classname, fieldname) = D.content(d)
    value = check(d, input)
    early = early_check(d, value)
    late = late_check(d, model, early)
    class = N.class(network, classname)
    entry = class.data[fieldname]
    N.mutate!(entry) do nodes
        nodes .= late
    end
end

#-------------------------------------------------------------------------------------------
# Display.

function nodes_shortline(io::IO, model::Model, d::D.NodeField)
    Field = D.CamelCaseSingular(d)
    c, f = D.content(d)
    network = NF.network(model)
    class = N.class(network, c)
    entry = class.data[f]
    N.read(entry) do data
        print(io, "$Field: [$(EN.join_elided(data, ", "))]")
    end
end
