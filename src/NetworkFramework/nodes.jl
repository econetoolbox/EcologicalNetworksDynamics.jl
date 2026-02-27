"""
Typical setup for a component bringing new data to a network class.
"""
macro node_data_component(input...)
    quote
        $define_node_data_component($__module__, $(Meta.quot.(input)...))
        nothing
    end
end

function define_node_data_component(
    mod::Module,
    # Short field name.
    field::Symbol,
    T::Type,
    # Provide name with the dispatcher (+ capitalized version).
    nd::NodeData,
    ND::NodeData;
    #---------------------------------------------------------------------------------------
    # Extension points.

    # Code for extra blueprints, evaluated within the blueprints module.
    Blueprints = nothing,

    # Extra requirements for the component.
    requires = (),

    # Raise to produce a 'Flat' blueprint
    # expanding the same scalar value to the whole class.
    # If raised, provide the argument type for component-call constructor.
    flat_blueprint = nothing,
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
    blueprints =
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
    blueprints.eval(
        quote
            mutable struct Raw <: Blueprint
                $field::Vector{$T}
                $class::Brought(Class)
                Raw($field, $class = _Class) = new(construct(Vector{$T}, $field), $class)
            end
            F.implied_blueprint_for(bp::Raw, ::_Class) = Class(length(bp.$field))
            F.early_check(bp::Raw) = $nodes_raw_early_check(nd, bp.$field)
            F.late_check(raw, bp::Raw, model) =
                nodes_raw_late_check(nd, raw, bp.$field, model)
            F.expand!(raw, ::Raw, values) = expand_from_vector!(raw, values)
            expand_from_vector!(raw, vec) = add_field!(N.class(raw, class), data, vec)
            @blueprint Raw "raw values"
            export Raw
        end,
    )

    # From a node-indexed map.
    blueprints.eval(
        quote
            mutable struct Map <: Blueprint
                $field::Map{$T}
                $class::Brought(Class)
                Map($field, sp = _Class) = new(graphdataconvert(Map{$T}, $field), sp)
            end
            F.implied_blueprint_for(bp::Map, ::_Class) = Class(refspace(bp.$field))
            F.early_check(bp::Map) = nodes_map_early_check(nd, bp.$field)
            F.late_check(raw, bp::Map, model) = nodes_map_late_check(nd, bp.$field, model)
            F.expand!(raw, bp::Map, values) = expand_from_vector!(raw, values)
            @blueprint Map "[$class => $data] map"
            export Map
        end,
    )

    # From a scalar broadcasted to all nodes in the class (if meaningful).
    if !isnothing(flat_blueprint)
        blueprints.eval(
            quote
                mutable struct Flat <: Blueprint
                    $field::$T
                end
                F.early_check(bp::Flat) = check_value(nd, bp.$field)
                F.expand!(raw, bp::Flat, _) =
                    expand_from_vector!(raw, fill(bp.$field, n_nodes(raw, $class)))
                @blueprint Flat "uniform value" depends(Class)
                export Flat
            end,
        )
    end

    # Any extra blueprint code.
    blueprints.eval(Blueprints)

    # ======================================================================================
    # The component itself and generic blueprints constructors.

    ND = typeof(nd)
    mod.eval(
        quote
            @component $Data{Internal} requires($Class, $(requires...)) blueprints($Data_)
            C.component(::$ND) = $Data

            function (::$_Data)($field)
                $field = @tographdata $field {Vector, Map}{$T}
                if $field isa Vector
                    $Data.Raw($field)
                else
                    $Data.Map($field)
                end
            end
        end,
    )

    if !isnothing(flat_blueprint)
        R = flat_blueprint # Receiver type.
        mod.eval(quote
            (::$_Data)($field::$R) = $Data.Flat($field)
        end)
    end

    # ======================================================================================
    # Queries.

    M = Symbol(Data, :Methods)
    m = :(mod($mod))
    get_data = Symbol(:get_, data)

    mod.eval.(
        (
            quote
                module $M # (to not pollute invokation scope)
                import EcologicalNetworksDynamics:
                    Views, @method, Internal, Model, NetworkConfig
                const nd = $nd
                const (class, data) = NetworkConfig.content(nd)

                $get_data(::Internal, m::Model) = Views.nodes_view(m, class, data)
                # XXX: how come set_data! is not needed anymore?
                @method $m $M.$get_data read_as($data) depends($Data)

                end
            end
        ).args,
    )

    # Specialize value checking prior to writing to views if any.

    # ======================================================================================
    # Display.
    N = Networks
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

check(::Dispatcher, T::Type, value) = inputconvert(T, value)
check_with_ref(d::Dispatcher, T::Type, value, i::Int) =
    try
        check(d, T, value)
    catch e
        e isa InputError || rethrow(e)
        inerr("At node index [$i]:\n$(e.mess)", rethrow)
    end
check_with_ref(d::Dispatcher, T::Type, value, l::Symbol) =
    try
        check(d, T, value)
    catch e
        e isa InputError || rethrow(e)
        inerr("At node with label $(repr(l)):\n$(e.mess)", rethrow)
    end

#-------------------------------------------------------------------------------------------
# Check against a model value, assuming the type and raw value is already correct.

check(::Dispatcher, ::Model, value) = value # Nothing to check by default.

function check_with_ref(d::NodeData, m::Model, value, i::Int, l::Symbol)
    try
        check(d, m, value, l)
    catch e
        e isa InputError || rethrow(e)
        inerr("At node with label $(repr(l)) ([$i]):\n$(e.mess)", rethrow)
    end
end

# Specialize the above, and automatically infer any reference type from the other one.
function check_with_ref(d::NodeData, m::Model, value, i::Int)
    network = F.value(m)
    class = D.class(d)
    index = N.index(network, class)
    l = N.to_label(index, i)
    check_with_ref(d, value, m, l, i)
end
function check_with_ref(d::NodeData, m::Model, value, l::Symbol)
    network = F.value(m)
    class = D.class(d)
    index = N.index(network, class)
    i = N.to_index(index, l)
    check_with_ref(d, value, m, l, i)
end

#-------------------------------------------------------------------------------------------
# Construct: any input is possible, but we don't know anything about the model yet.

construct(::Dispatcher, T::Type, value) = check(T, value)
construct_with_ref(d::NodeData, T::Type, value, r::Ref) = check_with_ref(d, T, value, r)
construct_from_iterable(d::NodeData, T::Type, iter) =
    try
        [construct_with_ref(d, T, value, i) for (i, value) in enumerate(iter)]
    catch e
        e isa InputError || rethrow(e)
        inerr("When constructing $d from iterable:\n$(e.mess)", rethrow)
    end
construct_from_map(d::NodeData, T::Type, map) =
    try
        parse(Map{<:Any,T}, map)
    catch e
        e isa InputError || rethrow(e)
        inerr("When constructing $d from map:\n$(e.mess)", rethrow)
    end

#-------------------------------------------------------------------------------------------
# Early-check: correct type, unchecked values, no model information yet.

function early_check(d::NodeData, vec::Vector)
    T = eltype(vec)
    data = T[]
    for (i, value) in enumerate(vec)
        try
            push!(data, check_with_ref(d, T, value, i))
        catch e
            e isa InputError || rethrow(e)
            F.checkfails("When checking $d values array:\n$(e.mess)", rethrow)
        end
    end
    data
end

function early_check(d::NodeData, map::Map)
    R, T = reftype(map), valtype(map)
    try
        parse(Map{R,T}, map) # Re-parse in case blueprint was mutated.
    catch e
        e isa InputError || rethrow(e)
        inerr("When checking $d values map:\n$(e.message)", rethrow)
    end
end

#-------------------------------------------------------------------------------------------
# Late-check: correct type, checked values, model information is now available.

function late_check(nd::NodeData, m::Model, values::Vector)
    # Check number of values first.
    network = NF.network(m)
    class = D.class(nd)
    n = N.n_nodes(network, class)
    l = length(values)
    n == l || F.checkfails("Wrong number of values received for $nd: expected $n, got $l.")
    labels = N.node_labels(network, class)
    # Then convert values one by one.
    map(enumerate(zip(labels, values))) do (i, (label, value))
        try
            check(nd, m, value, label, i)
        catch e
            e isa InputError || rethrow(e)
            F.checkfails(
                "Incorrect value at index [$i] ($(repr(label))):\n$(e.message)",
                rethrow,
            )
        end
    end
end

# HERE: review and fit into the above.
function nodes_map_late_check(nd::NodeData, raw::Network, map::Map, model::Model)
    # Check labels first.
    labels = node_labels(raw, class)
    exp = Set()
    act = Set(keys(map))
    miss = setdiff(exp, act)
    if !isempty(miss)
        miss = join_elided(sort!(collect(miss)), ", ", " and ")
        checkfails("Missing for $nd, no value provided for $miss.")
    end
    unexp = setdiff(act, exp)
    if !isempty(unexp)
        unexp = join_elided(sort!(collect(miss)), ", ", " and ")
        a, s = length(unexp) == 1 ? (" a", "") : ("", "s")
        checkfails("Not$a $(repr(class)) name$s: $unexp.")
    end
    # Then reorder values one by one into a vector.
    try
        map(labels) do label
            value = map[label]
            check_value(nd, model, value, label)
        end
    catch e
        e isa ValueError && checkfails(
            "Incorrect value for label $(repr(label)) [$i]:\n$(e.message)",
            rethrow,
        )
        rethrow(e)
    end
end

# HERE: merge with the above?
function late_check_vec(d::Dispatcher, m::Model, vec::Vector)
    net = F.value(m)
    class = D.class(d)
    index = N.index(net, class)
    names = N.labels(index)
    try
        for (name, (i, value)) in zip(names, enumerate(vec))
            check_with_ref(d)
        end
    catch e
        e isa InputError || rethrow(e)
        F.checkfails("When checking $d values array against model:\n$(e.message)", rethrow)
    end
    vec
end

#-------------------------------------------------------------------------------------------
# Mutation: called when setting through a view.
# Input may be anything, but the underlying model value can be assumed to be correct.

# HERE: use.
mutate_check(d::Dispatcher, T::Type, m::Model, value, ref) =
    try
        value = check_with_ref(d, T, value, ref)
        check_with_ref(d, m, value, ref)
    catch e
        e isa InputError || rethrow(e)
        inerr("When attempting to mutate $d node value:\n$(e.message)", rethrow)
    end

#-------------------------------------------------------------------------------------------
# Display.

function nodes_shortline(io::IO, model::Model, nd::NodeData, Data::Symbol)
    c, d = content(nd)
    network = EN.value(model)
    class = N.class(network, c)
    entry = class.data[d]
    N.read(entry) do data
        print(io, "$Data: [$(join_elided(data, ", "))]")
    end
end

