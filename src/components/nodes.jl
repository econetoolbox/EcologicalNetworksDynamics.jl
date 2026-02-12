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
    class, data = content(nd)
    Class, Data = content(ND)
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
                        Blueprint,
                        Framework,
                        Networks,
                        GraphDataInputs,
                        Views,
                        @blueprint,
                        NetworkConfig
                    using .Networks
                    using .Framework
                    using .GraphDataInputs
                    using .NetworkConfig
                    const N = Networks
                    const F = Framework
                    const T = GraphDataInputs # "T"ypes.
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
                Raw($field, $class = _Class) =
                    new(graphdataconvert(Vector{$T}, $field), $class)
            end
            F.implied_blueprint_for(bp::Raw, ::_Class) = Class(length(bp.$field))
            F.early_check(bp::Raw) = nodes_raw_early_check(nd, bp.$field)
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
                $field::T.Map{$T}
                $class::Brought(Class)
                Map($field, sp = _Class) = new(graphdataconvert(T.Map{$T}, $field), sp)
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
# Extract implementation detail to ease Revise work.

#-------------------------------------------------------------------------------------------
# Raw blueprint.

nodes_raw_early_check(nd::NodeData, values::Vector) =
    for (i, value) in enumerate(values)
        try
            check_value(nd, value)
        catch e
            e isa ValueError && checkfails(
                "When checking vector data for $nd \
                 at index [$i]:\n$(e.message)",
                rethrow,
            )
            rethrow(e)
        end
    end

function nodes_raw_late_check(nd::NodeData, raw::Network, values::Vector, model::Model)
    # Check number of values first.
    n = n_nodes(raw, class)
    l = length(values)
    n == l || checkfails("Wrong number of values received for $nd: expected $n, got $l.")
    labels = node_labels(raw, class)
    # Then convert values one by one.
    map(enumerate(zip(labels, values))) do (i, (label, value))
        try
            check_value(nd, model, value, label, i)
        catch e
            e isa ValueError && checkfails(
                "Incorrect value at index [$i] ($(repr(label))):\n$(e.message)",
                rethrow,
            )
            rethrow(e)
        end
    end
end

#-------------------------------------------------------------------------------------------
# Map blueprint.

nodes_map_early_check(nd::NodeData, values::Vector) =
    for (label, value) in values
        try
            check_value(nd, label)
        catch e
            e isa ValueError && checkfails(
                "When checking map data for $nd \
                 for label [$(repr(label))]:\n$(e.message)",
                rethrow,
            )
            rethrow(e)
        end
    end

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
