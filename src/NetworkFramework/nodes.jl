# Typical setup for a component bringing a new field to a network class.
# This abstracts over both subclass/sparse and root/dense fields,
# but any code easily moved to `sparse_nodes.jl` lives there.

# Raise to produce a 'Flat' blueprint
# expanding the same scalar value to the whole class,
# and allow flattening assignment.
# If raised, provide the argument type for component-call constructor.
flat(d::AbstractNodeField) = D.type(d)
may_flat(d::AbstractNodeField) = !isnothing(flat(d))

function define_node_field_component(
    mod::Module,
    d::NodeField;
    blueprints = [], # Extra blueprints for the component.
    requires = [], # Extra requirements for the component.
)

    #---------------------------------------------------------------------------------------
    # Extract particular information for this (class, field) pair.
    nc = NodeClass(d)
    Class = D.CamelCaseSingular(nc)
    class, field = D.content(d)
    value, values, Value, Values, short = D.name_variants(d)
    T = D.type(d)

    # Use it to generate adequate code.
    Value_ = Symbol(Value, :_) # Blueprints module name.
    _Value = Symbol(:_, Value) # Component type name.

    # ======================================================================================
    # Blueprints for the component.

    # Prepare dedicated blueprints module and populate namespace.
    bpmod =
        mod.eval.(
            (
                quote
                    module $Value_
                    import EcologicalNetworksDynamics:
                        EN, Networks, N, Framework, F, NF, D, Blueprint, Brought, Views
                    const Class = $mod.$Class
                    const _Class = typeof(Class)
                    const d = $d
                    const (class, field) = D.content(d)
                    end
                end
            ).args
        ) |> last

    #---------------------------------------------------------------------------------------
    # From raw values.
    bpmod.eval(
        quote
            mutable struct Raw <: Blueprint
                $field::Vector{$T}
                $class::Brought(Class)
                Raw($field, $class) = new($construct_raw(d, $field), $class)
                Raw($field; $class = _Class) = Raw($field, $class)
            end
            F.implied_blueprint_for(bp::Raw, ::_Class) =
                $implied_class_from_raw(d, Class, bp.$field)
            F.early_check(bp::Raw) = $early_check(d, bp.$field)
            F.late_check(model, bp::Raw, early_data) = $late_check(d, model, early_data)
            F.expand!(model, ::Raw, late_data) = $expand!(d, model, late_data)
            NF.define_blueprint(Raw, "raw values")
            export Raw
        end,
    )

    #---------------------------------------------------------------------------------------
    # From a node-indexed map.

    bpmod.eval(
        quote
            mutable struct Map <: Blueprint
                $field::EN.Map{$T}
                $class::Brought(Class) # TODO: not exactly useful? Keep for consistency?
                Map($field, $class) = new($construct_map(d, $field), $class)
                Map($field; $class = _Class) = Map($field, $class)
            end
            F.implied_blueprint_for(bp::Map, ::_Class) =
                $implied_class_from_map(d, Class, bp.$field)
            F.early_check(bp::Map) = $early_check(d, bp.$field)
            F.late_check(model, bp::Map, early_data) = $late_check(d, model, early_data)
            F.expand!(model, bp::Map, late_data) = $expand!(d, model, late_data)
            NF.define_blueprint(Map, "[$class => $field] map")
            export Map
        end,
    )

    #---------------------------------------------------------------------------------------
    # From a scalar broadcasted to all nodes in the class (if meaningful).
    if may_flat(d)
        bpmod.eval(
            quote
                mutable struct Flat <: Blueprint
                    $field::$T
                end
                F.early_check(bp::Flat) = $early_check_flat(d, bp.$field)
                F.late_check(model, bp::Flat, early_data) =
                    $late_check_flat(d, model, early_data)
                F.expand!(model, bp::Flat, late_data) = $expand_flat!(d, model, late_data)
                NF.define_blueprint(Flat, "uniform value"; depends = [Class])
                export Flat
            end,
        )
    end

    # ======================================================================================
    # The component itself and generic blueprints constructors.

    DT = typeof(d)
    comp = mod.eval(
        quote
            NF.define_component(
                $(Meta.quot(Value)),
                $mod;
                requires = $requires,
                blueprints = [$bpmod, $(blueprints...)],
            )
        end,
    )
    C = typeof(comp)
    mod.eval(
        quote
            $D.component(::$DT) = $comp
            (::$_Value)($field, args...; kwargs...) =
                $construct($d, $Value, $field, args...; kwargs...)
        end,
    )

    if may_flat(d)
        R = flat(d) # Receiver type.
        mod.eval(quote
            (::$_Value)($field::$R) = $Value.Flat($field)
        end)
    end

    # Queries.
    M = Symbol(Values, :_Methods)
    prop = [value]
    xp =
        (
            quote
                module $M
                using EcologicalNetworksDynamics: V, NF, D, Network, Model
                const d = $d
                const prop = $prop
                const C = $C
                get_value(::Network, m::Model) = V.data_view(m, d)
                NF.define_method(get_value; read_as = prop, depends = [C])
                if !D.readonly(d)
                    set_value!(::Network, m::Model, input) = assign!(d, m, input)
                    NF.define_method(set_value!; write_as = prop, depends = [C])
                end
                end
            end
        ).args |> last
    mod.eval(xp)

    # Display.
    mod.eval(quote
        $F.shortline(io::IO, model::Model, ::$C) = $nodes_shortline(io, model, $d)
    end)
end

# ==========================================================================================
# Extract implementation detail to ease Revise work + specify extension points.

#-------------------------------------------------------------------------------------------
# Check data values without model information, against the target type.

check(d::AbstractNodeField, value) = inputconvert(D.type(d), value)

check_with_ref(d::AbstractNodeField, value, i::Int) =
    try
        check(d, value)
    catch e
        e isa InputError || rethrow(e)
        inerr("At node index [$i]:\n$(e.mess)", rethrow)
    end
check_with_ref(d::AbstractNodeField, value, l::Symbol) =
    try
        check(d, value)
    catch e
        e isa InputError || rethrow(e)
        inerr("At node with label $(repr(l)):\n$(e.mess)", rethrow)
    end

#-------------------------------------------------------------------------------------------
# Check against a model value, assuming the type and raw value is already correct.

check(::AbstractNodeField, ::Model, value, ::Int, ::Symbol) = value # No check by default.

#-------------------------------------------------------------------------------------------
# Check against both the type and then immediately the model (useful for mutating).
# To this end, wrap the model in the following marker.
struct WholeCheck
    model::Model
end
get_model(w::WholeCheck) = w.model
get_model(m::Model) = m

function check(d::AbstractNodeField, whole::WholeCheck, value)
    converted = check(d, value)
    check(d, whole.model, converted)
end

# Abstract over either whole check or just-model check.
function check_with_ref(d::AbstractNodeField, against::Model, value, i::Int, l::Symbol)
    try
        value = check(d, value)
        check(d, against, value, i, l)
    catch e
        e isa InputError || rethrow(e)
        inerr("At node with label $(repr(l)) ([$i]):\n$(e.mess)", rethrow)
    end
end

# Use the model to automatically infer any reference type from the other one.
function check_with_ref(d::AbstractNodeField, against, value, i::Int)
    model = get_model(against)
    network = NF.network(model)
    class = D.class(d)
    index = N.index(network, class)
    l = N.to_label(index, i)
    check_with_ref(d, model, value, i, l)
end
function check_with_ref(d::AbstractNodeField, against, value, l::Symbol)
    model = get_model(against)
    network = NF.network(model)
    class = D.class(d)
    index = N.index(network, class)
    i = N.to_index(index, l)
    check_with_ref(d, model, value, i, l)
end

#-------------------------------------------------------------------------------------------
# Construct: any input is possible, but we don't know anything about the model yet.

function construct_raw(d::AbstractNodeField, raw)
    T = D.type(d)
    try
        v = inputconvert(Vector{T}, raw)
        for (i, value) in enumerate(v)
            check_with_ref(d, value, i)
        end
        v
    catch e
        e isa InputError || rethrow(e)
        inerr("When constructing $d from raw values:\n$(e.mess)", rethrow)
    end
end

function construct_map(d::AbstractNodeField, map)
    T = D.type(d)
    try
        out = inputconvert(Map{T}, map)
        for (l, v) in out
            check_with_ref(d, v, l)
        end
        out
    catch e
        e isa InputError || rethrow(e)
        inerr("When constructing $d from map:\n$(e.mess)", rethrow)
    end
end

function construct(d::NodeField, Field::Component, input; kwargs...)
    @kwargs_helpers(kwargs)
    nc = NodeClass(d)
    class = D.class(nc)
    Class = take_or!(class, D.component(nc), Any)
    no_unused_arguments()
    kwargs = [class => Class]
    T = D.type(d)
    tries = []
    if may_flat(d)
        push!(tries, T => v -> Field.Flat(v))
    end
    push!(tries, Vector{T} => v -> Field.Raw(v; kwargs...))
    push!(tries, Map{T} => m -> Field.Map(m; kwargs...))
    input_try(input, tries...)
end

#-------------------------------------------------------------------------------------------
# Early-check: correct type, unchecked values, no model information yet.

function early_check(d::AbstractNodeField, vec::Vector)
    T = eltype(vec)
    data = T[]
    for (i, value) in enumerate(vec)
        value = try
            check_with_ref(d, value, i)
        catch e
            e isa InputError || rethrow(e)
            F.checkfails("When checking $d values array:\n$(e.mess)", rethrow)
        end
        push!(data, value)
    end
    data
end

function early_check(d::AbstractNodeField, map::Map)
    T, R = valtype(map), reftype(map)
    try
        map = inputconvert(Map{T,R}, map) # Re-parse in case the map was mutated.
        for (label, value) in map
            map[label] = check_with_ref(d, value, label)
        end
        map
    catch e
        e isa InputError || rethrow(e)
        F.checkfails("When checking $d values map:\n$(e.mess)", rethrow)
    end
end

function early_check_flat(d::AbstractNodeField, value)
    try
        check(d, value)
    catch e
        e isa InputError || rethrow(e)
        F.checkfails("When checking $d flat value:\n$(e.mess)", rethrow)
    end
end

#-------------------------------------------------------------------------------------------
# Late-check: correct type, checked values, model information is now available.

# Just pass the data without checking by default.
late_check(::AbstractNodeField, ::Model, early_data) = early_data

# Typical vector case for Raw blueprint.
function late_check(d::AbstractNodeField, model::Model, vec::Vector)
    # Check number of values first.
    network = NF.network(model)
    class = D.class(d)
    n = N.n_nodes(network, class)
    l = length(vec)
    n == l || F.checkfails("Wrong number of values received for $d: \
                            expected $n, got $l.")
    labels = N.node_labels(network, class)
    # Then check values one by one, with context to produce useful reports.
    map(enumerate(zip(labels, vec))) do (i, (label, value))
        try
            check_with_ref(d, model, value, i, label)
        catch e
            e isa InputError || rethrow(e)
            F.checkfails("When checking $d values array against model:\n$(e.mess)", rethrow)
        end
    end
end

# Typical map case for Map blueprint.
function late_check(d::AbstractNodeField, model::Model, map::Map{<:Any,Symbol})
    # Check labels first.
    network = NF.network(model)
    class = D.class(d)
    labels = N.node_labels(network, class)
    exp = Set(labels)
    act = Set(keys(map))
    miss = setdiff(exp, act)
    if !isempty(miss)
        miss = EN.join_elided(sort!(collect(miss)), ", ", " and ")
        F.checkfails("Missing for $d, no value provided for $miss.")
    end
    unexp = setdiff(act, exp)
    if !isempty(unexp)
        unexp = EN.join_elided(sort!(collect(unexp)), ", ", " and ")
        a, s = length(unexp) == 1 ? (" a", "") : ("", "s")
        F.checkfails("Not$a $(repr(class)) name$s: $unexp.")
    end
    # Then reorder values one by one into a vector.
    try
        [check_with_ref(d, model, map[label], label) for label in labels]
    catch e
        e isa InputError || rethrow(e)
        F.checkfails("When checking $d values map against model:\n$(e.mess)", rethrow)
    end
end

# Same with index references instead.
function late_check(d::AbstractNodeField, model::Model, map::Map{<:Any,Int})
    # Check indices first.
    network = NF.network(model)
    class = D.class(d)
    n = N.n_nodes(network, class)
    miss = Int[]
    for exp in 1:n
        haskey(map, exp) && continue
        push!(miss, exp)
    end
    if !isempty(miss)
        miss = EN.join_elided(miss, ", ", " and ")
        s = length(miss) == 1 ? "" : "s"
        F.checkfails("Missing for $d, no value provided for node$s $miss.")
    end
    unexp = miss
    for act in keys(map)
        act in 1:n && continue
        push!(unexp, act)
    end
    if !isempty(unexp)
        unexp = EN.join_elided(unexp, ", ", " and ")
        indices, s = length(unexp) == 1 ? ("index", "") : ("indices", "s")
        F.checkfails("Invalid $indices for class $(repr(class)) with $n node$s: $unexp.")
    end
    # Then reorder values one by one into a vector.
    try
        [check_with_ref(d, model, map[i], i) for i in 1:n]
    catch e
        e isa InputError || rethrow(e)
        F.checkfails("When checking $d values map against model:\n$(e.mess)", rethrow)
    end
end

# Not much to do by default in this situation, just keep as an extension point.
late_check_flat(::AbstractNodeField, ::Model, value) = value

#-------------------------------------------------------------------------------------------
# Implied class blueprint.

function implied_class_from_raw(::NodeField, Class, raw)
    n = length(raw)
    Class.Number(n)
end

function implied_class_from_map(::NodeField, Class, map::Map{<:Any,Symbol})
    refs = NF.keys(map)
    Class.Names(collect(refs))
end

function implied_class_from_map(::NodeField, Class, map::Map{<:Any,Int})
    n = length(map) # (assuming no hole) TODO: how is that enforced?
    Class.Number(n)
end

#-------------------------------------------------------------------------------------------
# Expansion: input is completely trusted, just fill the inner network from late data.

function expand!(d::AbstractNodeField, model::Model, late_data::Vector)
    network = NF.network(model)
    (classname, fieldname) = D.content(d)
    class = N.class(network, classname)
    N.add_field!(class, fieldname, late_data)
end

# Special case flat-blueprint.
function expand_flat!(d::AbstractNodeField, model::Model, late_data)
    network = NF.network(model)
    class = D.class(d)
    n = N.n_nodes(network, class)
    vec = fill(late_data, n)
    expand!(d, model, vec)
end

#-------------------------------------------------------------------------------------------
# Mutation: called when setting through a view.
# Input may be anything,
# but the underlying model value and the reference can be assumed to be correct.

mutate_check(d::AbstractNodeField, model::Model, value, ref) =
    try
        check_with_ref(d, WholeCheck(model), value, ref)
    catch e
        e isa InputError || rethrow(e)
        inerr("When attempting to mutate $d node value:\n$(e.mess)", rethrow)
    end

#-------------------------------------------------------------------------------------------
# Assignment: called when setting all values at once through a property.
# Input may be anything, but the underlying model value can be assumed to be correct.

function assign!(d::NodeField, model::Model, input)
    tries = [assign_raw!, assign_map!]
    if may_flat(d)
        push!(tries, assign_flat!)
    end
    first_err = nothing
    for attempt! in tries
        try
            attempt!(d, model, input)
            return
        catch e
            if isnothing(first_err)
                first_err = e
            end
            continue
        end
    end
    throw(first_err)
end

# Assume the assignment input is made of raw values.
function assign_raw!(d::NodeField, model::Model, input)
    network = NF.network(model)
    (classname, fieldname) = D.content(d)
    raw = construct_raw(d, input)
    early = early_check(d, raw)
    late = late_check(d, model, early)
    class = N.class(network, classname)
    entry = class.data[fieldname]
    N.write!(entry) do nodes
        for (i, new_value) in enumerate(late)
            nodes[i] = new_value
        end
    end
end

# Assume the assignment input is made of mapped values.
function assign_map!(d::NodeField, model::Model, input)
    network = NF.network(model)
    (classname, fieldname) = D.content(d)
    early = early_check(d, input) # Reparsed anyway.
    late = late_check(d, early)
    class = N.class(network, classname)
    index = class.index
    entry = class.data[fieldname]
    N.write!(entry) do nodes
        for (label, new_value) in late
            i = N.to_index(index, label)
            nodes[i] = new_value
        end
    end
end

# Assume the assignment input is a single value to flatten to all nodes.
function assign_flat!(d::NodeField, model::Model, input)
    network = NF.network(model)
    (classname, fieldname) = D.content(d)
    raw = check(d, input)
    early = early_check(d, raw)
    late = late_check(d, model, early)
    class = N.class(network, classname)
    entry = class.data[fieldname]
    N.write!(entry) do nodes
        nodes .= late
    end
end

#-------------------------------------------------------------------------------------------
# Display.

function nodes_shortline(io::IO, model::Model, d::NodeField)
    Field = D.CamelCaseSingular(d)
    c, f = D.content(d)
    network = NF.network(model)
    class = N.class(network, c)
    entry = class.data[f]
    N.read(entry) do data
        print(io, "$Field: [$(EN.join_elided(data, ", "))]")
    end
end
