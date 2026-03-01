"""
Typical setup for a component bringing new data to a network class.
"""
macro node_data_component(input...)
    quote
        $define_node_data_component($__module__, $(Meta.quot.(input)...))
        nothing
    end
end

# Raise to produce a 'Flat' blueprint
# expanding the same scalar value to the whole class,
# and allow flattening assignment.
# If raised, provide the argument type for component-call constructor.
flat(nd::NodeData) = D.type(nd)
may_flat(nd::NodeData) = !isnothing(flat(nd))

function define_node_data_component(
    mod::Module,
    nd::NodeData,
    #---------------------------------------------------------------------------------------
    # Extension points.
    # Code for extra blueprints, evaluated within the blueprints module.
    Blueprints = nothing,
    # Extra requirements for the component.
    requires = (),
)
    #---------------------------------------------------------------------------------------
    class, data = D.content(nd)
    Class, Data = D.content(ND)
    Data_ = Symbol(Data, :_) # Blueprints module name.
    _Data = Symbol(:_, Data) # Component type name.
    # Dispatch to this node class field.

    # ======================================================================================
    # Blueprints for the component.

    # Prepare dedicated blueprints module and populate namespace.
    Blueprints =
        mod.eval.(
            (
                quote
                    module $Data_
                    import EcologicalNetworksDynamics:
                        Blueprint, Framework, Networks, Views, @blueprint, NetworkConfig
                    using .Networks
                    using .Framework
                    using .NetworkConfig
                    const N = Networks
                    const F = Framework
                    const Class = $mod.$Class
                    const _Class = typeof(Class)
                    const nd = $nd
                    const (class, data) = NetworkConfig.content(nd)
                    end
                end
            ).args
        ) |> last


    # From raw values.
    Blueprints.eval(
        quote
            mutable struct Raw <: Blueprint
                $field::Vector{$T}
                $class::Brought(Class)
                Raw($field, $class = _Class) = new($construct_raw(nd, $field), $class)
                Raw($field::Vector{$T}, $class = _Class) = new($field, $class) # Alias.
            end
            F.implied_blueprint_for(bp::Raw, ::_Class) = Class(length(bp.$field))
            F.early_check(bp::Raw) = $early_check(nd, bp.$field)
            F.late_check(model, bp::Raw, early_data) = $late_check(nd, model, early_data)
            F.expand!(model, ::Raw, late_data) = $expand!(nd, model, late_data)
            @blueprint Raw "raw values"
            export Raw
        end,
    )

    # From a node-indexed map.
    Blueprints.eval(
        quote
            mutable struct Map <: Blueprint
                $field::Map{$T}
                $class::Brought(Class)
                Map($field, sp = _Class) = new($construct_map(nd, $field), sp)
            end
            F.implied_blueprint_for(bp::Map, ::_Class) = Class(keys(bp.$field))
            F.early_check(bp::Map) = $early_check(nd, bp.$field)
            F.late_check(model, bp::Map, early_data) = $late_check(nd, model, early_data)
            F.expand!(model, bp::Map, late_data) = $expand!(nd, model, late_data)
            @blueprint Map "[$class => $data] map"
            export Map
        end,
    )

    # From a scalar broadcasted to all nodes in the class (if meaningful).
    if may_flat(nd)
        Blueprints.eval(
            quote
                mutable struct Flat <: Blueprint
                    $field::$T
                end
                F.early_check(bp::Flat) = $early_check(nd, bp.$field)
                F.late_check(model, bp::Float, early_data) =
                    $late_check(nd, model, early_data)
                F.expand!(model, bp::Flat, late_data) = $expand_flat!(nd, model, late_data)
                @blueprint Flat "uniform value" depends(Class)
                export Flat
            end,
        )
    end

    # Any extra blueprint code.
    Blueprints.eval(Blueprints)

    # ======================================================================================
    # The component itself and generic blueprints constructors.

    ND = typeof(nd)
    mod.eval(
        quote
            @component $Data{Network} requires($Class, $(requires...)) Blueprints($Data_)
            C.component(::$ND) = $Data
            (::$_Data)($field) = $construct($nd, $Data, $field)
        end,
    )

    if may_flat(nd)
        R = flat(nd) # Receiver type.
        mod.eval(quote
            (::$_Data)($field::$R) = $Data.Flat($field)
        end)
    end

    # ======================================================================================
    # Queries.

    M = Symbol(Data, :Methods)
    m = :(mod($mod))
    get_data = Symbol(:get_, data)

    Methods =
        mod.eval.(
            (
                quote
                    module $M # (to not pollute invokation scope)
                    import EcologicalNetworksDynamics:
                        Network, Views, @method, Model, NetworkConfig
                    const nd = $nd
                    const (class, data) = NetworkConfig.content(nd)

                    $get_data(::Network, m::Model) = Views.nodes_view(m, class, data)
                    @method $m $M.$get_data read_as($data) depends($Data)

                    end
                end
            ).args,
        ) |> last

    if !D.readonly(nd)
        Methods.eval(quote
            $set_data(::Network, m::Model, input) = $assign!(nd, m, input)
            @method $m $M.$set_data write_as($data) depends($Data)
        end)
    end

    # ======================================================================================
    # Display.
    mod.eval(
        quote
            $Framework.shortline(io::IO, model::Model, ::$_Data) =
                nodes_shortline(io, model, $nd, $(Meta.quot(Data)))
        end,
    )
end

# ==========================================================================================
# Extract implementation detail to ease Revise work + specify extension points.

#-------------------------------------------------------------------------------------------
# Check data values without model information, against the target type.

check(nd::NodeData, value) = inputconvert(D.type(nd), value)

check_with_ref(nd::NodeData, value, i::Int) =
    try
        check(nd, value)
    catch e
        e isa InputError || rethrow(e)
        inerr("At node index [$i]:\n$(e.mess)", rethrow)
    end
check_with_ref(nd::NodeData, value, l::Symbol) =
    try
        check(nd, value)
    catch e
        e isa InputError || rethrow(e)
        inerr("At node with label $(repr(l)):\n$(e.mess)", rethrow)
    end

#-------------------------------------------------------------------------------------------
# Check against a model value, assuming the type and raw value is already correct.

check(::NodeData, ::Model, value) = value # Nothing to check by default.

#-------------------------------------------------------------------------------------------
# Check against both the type and then immediately the model (useful for mutating).
# To this end, wrap the model in the following marker.
struct WholeCheck
    model::Model
end
get_model(w::WholeCheck) = w.model
get_model(m::Model) = m

function check(nd::NodeData, whole::WholeCheck, value)
    converted = check(nd, value)
    check(nd, whole.model, converted)
end

# Abstract over either whole check or just-model check.
function check_with_ref(d::NodeData, against, value, i::Int, l::Symbol)
    try
        check(d, against, value)
    catch e
        e isa InputError || rethrow(e)
        inerr("At node with label $(repr(l)) ([$i]):\n$(e.mess)", rethrow)
    end
end

# Use the model to automatically infer any reference type from the other one.
function check_with_ref(d::NodeData, against, value, i::Int)
    model = get_model(against)
    network = NF.network(model)
    class = D.class(d)
    index = N.index(network, class)
    l = N.to_label(index, i)
    check_with_ref(d, value, model, l, i)
end
function check_with_ref(d::NodeData, against, value, l::Symbol)
    model = get_model(against)
    network = NF.network(model)
    class = D.class(d)
    index = N.index(network, class)
    i = N.to_index(index, l)
    check_with_ref(d, value, model, l, i)
end

#-------------------------------------------------------------------------------------------
# Construct: any input is possible, but we don't know anything about the model yet.

construct(nd::NodeData, value) = check(nd, value)
construct_with_ref(nd::NodeData, value, r::Ref) = check_with_ref(nd, value, r)
function construct_raw(nd::NodeData, iter)
    try
        [construct_with_ref(nd, value, i) for (i, value) in enumerate(iter)]
    catch e
        e isa InputError || rethrow(e)
        inerr("When constructing $nd from iterable:\n$(e.mess)", rethrow)
    end
end
function construct_map(nd::NodeData, map)
    T = D.type(nd)
    try
        parse(Map{<:Any,T}, map)
    catch e
        e isa InputError || rethrow(e)
        inerr("When constructing $nd from map:\n$(e.mess)", rethrow)
    end
end

function construct(nd::NodeData, Data::Component, input)
    T = D.type(nd)
    input_try(input, Vector{T} => Data.Raw, Map{Ref,T} => Data.Map)
end

#-------------------------------------------------------------------------------------------
# Early-check: correct type, unchecked values, no model information yet.

function early_check(nd::NodeData, vec::Vector)
    T = eltype(vec)
    data = T[]
    for (i, value) in enumerate(vec)
        value = try
            check_with_ref(nd, value, i)
        catch e
            e isa InputError || rethrow(e)
            F.checkfails("When checking $nd values array:\n$(e.mess)", rethrow)
        end
        push!(data, value)
    end
    data
end

function early_check(nd::NodeData, map::Map)
    R, T = reftype(map), valtype(map)
    try
        map = parse(Map{R,T}, map) # Re-parse in case the map was mutated.
        for (label, value) in map
            map[label] = check_with_ref(nd, value, label)
        end
        map
    catch e
        e isa InputError || rethrow(e)
        inerr("When checking $nd values map:\n$(e.message)", rethrow)
    end
end

#-------------------------------------------------------------------------------------------
# Late-check: correct type, checked values, model information is now available.

# Just pass the data without checking by default.
late_check(::NodeData, ::Model, early_data) = early_data

# Typical vector case for Raw blueprint.
function late_check(nd::NodeData, model::Model, vec::Vector)
    # Check number of values first.
    network = NF.network(model)
    class = D.class(nd)
    n = N.n_nodes(network, class)
    l = length(vec)
    n == l || F.checkfails("Wrong number of values received for $nd: expected $n, got $l.")
    labels = N.node_labels(network, class)
    # Then check values one by one, with context to produce useful reports.
    map(enumerate(zip(labels, vec))) do (i, (label, value))
        try
            check_with_ref(nd, model, value, label, i)
        catch e
            e isa InputError || rethrow(e)
            F.checkfails(
                "When checking $nd values array against model:\n$(e.mess)",
                rethrow,
            )
        end
    end
end

# Typical map case for Map blueprint.
function late_check(nd::NodeData, model::Model, map::Map)
    # Check labels first.
    network = NF.network(model)
    class = D.class(nd)
    labels = N.node_labels(network, class)
    exp = Set(labels)
    act = Set(keys(map))
    miss = setdiff(exp, act)
    if !isempty(miss)
        miss = EN.join_elided(sort!(collect(miss)), ", ", " and ")
        F.checkfails("Missing for $nd, no value provided for $miss.")
    end
    unexp = setdiff(act, exp)
    if !isempty(unexp)
        unexp = EN.join_elided(sort!(collect(miss)), ", ", " and ")
        a, s = length(unexp) == 1 ? (" a", "") : ("", "s")
        F.checkfails("Not$a $(repr(class)) name$s: $unexp.")
    end
    # Then reorder values one by one into a vector.
    try
        Base.map(labels) do label
            value = map[label]
            F.check_with_ref(nd, model, value, label)
        end
    catch e
        e isa InputError || rethrow(e)
        F.checkfails("When checking $nd values map against model:\n$(e.mess)", rethrow)
    end
end


#-------------------------------------------------------------------------------------------
# Expansion: input is completely trusted, just fill the inner network from late data.

function expand!(nd::NodeData, model::Model, late_data::Vector)
    network = NF.network(model)
    (classname, fieldname) = D.content(nd)
    class = N.class(network, classname)
    N.add_field!(class, fieldname, late_data)
end

# Special case flat-blueprint.
function expand_flat!(nd::NodeData, model::Model, late_data)
    network = NF.network(model)
    class = D.class(nd)
    n = N.n_nodes(network, class)
    vec = fill(late_data, n)
    expand!(nd, model, vec)
end

#-------------------------------------------------------------------------------------------
# Mutation: called when setting through a view.
# Input may be anything,
# but the underlying model value and the reference can be assumed to be correct.

mutate_check(nd::NodeData, model::Model, value, ref) =
    try
        check_with_ref(nd, WholeCheck(model), value, ref)
    catch e
        e isa InputError || rethrow(e)
        inerr("When attempting to mutate $nd node value:\n$(e.mess)", rethrow)
    end

#-------------------------------------------------------------------------------------------
# Assignment: called when setting all values at once through a property.
# Input may be anything, but the underlying model value can be assumed to be correct.

function assign!(nd::NodeData, model::Model, input)
    tries = [assign_raw!, assign_map!]
    if may_flat(nd)
        push!(tries, assign_flat!)
    end
    first_err = nothing
    for attempt! in tries
        try
            attempt!(nd, model, input)
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
function assign_raw!(nd::NodeData, model::Model, input)
    network = NF.network(model)
    (classname, fieldname) = D.content(nd)
    raw = construct_raw(nd, input)
    early = early_check(nd, raw)
    late = late_check(nd, model, early)
    class = N.class(network, classname)
    entry = class.data[fieldname]
    N.write!(entry) do nodes
        for (i, new_value) in enumerate(late)
            nodes[i] = new_value
        end
    end
end

# Assume the assignment input is made of mapped values.
function assign_map!(nd::NodeData, model::Model, input)
    network = NF.network(model)
    (classname, fieldname) = D.content(nd)
    early = early_check(nd, input) # Reparsed anyway.
    late = late_check(nd, early)
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
function assign_flat!(nd::NodeData, model::Model, input)
    network = NF.network(model)
    (classname, fieldname) = D.content(nd)
    raw = check(nd, input)
    early = early_check(nd, raw)
    late = late_check(nd, model, early)
    class = N.class(network, classname)
    entry = class.data[fieldname]
    N.write!(entry) do nodes
        nodes .= late
    end
end

#-------------------------------------------------------------------------------------------
# Display.

function nodes_shortline(io::IO, model::Model, nd::NodeData, Data::Symbol)
    c, d = D.content(nd)
    network = NF.network(model)
    class = N.class(network, c)
    entry = class.data[d]
    N.read(entry) do data
        print(io, "$Data: [$(EN.join_elided(data, ", "))]")
    end
end
