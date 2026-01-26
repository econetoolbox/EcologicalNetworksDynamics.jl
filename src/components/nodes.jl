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
    # Data name and its class.
    class::Symbol,
    Class::Union{Symbol,Expr},
    data::Symbol,
    Data::Symbol;
    # Extension points.
    # Check value prior to writing through view, and associated failure message.
    check_value = ((_) -> true, ""),
    # Code for extra blueprints, evaluated within the code generated here.
    Blueprints = nothing,
)
    Data_ = Symbol(Data, :_) # Blueprints module name.
    _Data = Symbol(:_, Data) # Component type name.
    s_data, s_field, s_class = Meta.quot.((data, field, class)) # Symbol names.
    check_value_fn, bad_value_message = check_value
    N = Networks
    # For queries.
    M = Symbol(Data, :Methods)
    m = :(mod($mod))
    get_data = Symbol(:get_, data)
    xp = quote

        # ==================================================================================
        # Blueprints for the component.
        module $Data_
        import EcologicalNetworksDynamics:
            Blueprint, Framework, Networks, GraphDataInputs, Views, @blueprint, @ref
        using .Networks
        using .Framework
        using .GraphDataInputs
        const F = Framework
        const Class = $mod.$Class
        const _Class = typeof(Class)

        #-----------------------------------------------------------------------------------
        # From raw values.

        mutable struct Raw <: Blueprint
            $field::Vector{Float64}
            $class::Brought(Class)
            Raw($field, $class = _Class) =
                new(@tographdata($field, Vector{Float64}), $class)
        end
        F.implied_blueprint_for(bp::Raw, ::_Class) = Class(length(bp.$field))
        @blueprint Raw "raw values"
        export Raw

        F.early_check(bp::Raw) = check_nodes(check, bp.$field)
        function check(value, ref = nothing)
            $check_value_fn(value) && return value
            index = if isnothing(ref)
                ""
            else
                "[$(join(repr.(ref), ", "))]"
            end
            checkfails("$($bad_value_message): $name$index = $value.")
        end

        function F.late_check(raw, bp::Raw)
            (; $field) = bp
            S = n_nodes(raw, $s_class)
            @check_size $field S
        end

        F.expand!(raw, bp::Raw) = expand_from_vector!(raw, bp.$field)
        expand_from_vector!(raw, vec) =
            add_field!(class(raw, $s_class), $s_data, deepcopy(vec))

        #-----------------------------------------------------------------------------------
        # From a scalar broadcasted to all nodes in the class.

        mutable struct Flat <: Blueprint
            $field::Float64
        end
        @blueprint Flat "uniform value" depends(Class)
        export Flat

        F.early_check(bp::Flat) = check(bp.$field)
        F.expand!(raw, bp::Flat) =
            expand_from_vector!(raw, to_size(bp.$field, n_nodes(raw, $s_class)))


        #-----------------------------------------------------------------------------------
        # From a node-indexed map.

        mutable struct Map <: Blueprint
            $field::@GraphData Map{Float64}
            $class::Brought(Class)
            Map($field, sp = _Class) = new(@tographdata($field, Map{Float64}), sp)
        end
        F.implied_blueprint_for(bp::Map, ::_Class) = Class(refspace(bp.$field))
        @blueprint Map "[$($s_class) => $($s_data)] map"
        export Map

        F.early_check(bp::Map) = check_nodes(check, bp.$field)
        function F.late_check(raw, bp::Map)
            (; $field) = bp
            index = @ref raw.$class.index
            @check_list_refs $field $s_class index dense
        end

        function F.expand!(raw, bp::Map)
            index = @ref raw.$class.index
            vec = to_dense_vector(bp.$field, index)
            expand_from_vector!(raw, vec)
        end

        $Blueprints

        end

        # ==================================================================================
        # The component itself and generic blueprints constructors.

        @component $Data{Internal} requires($Class) blueprints($Data_)
        export $Data

        (::$_Data)($field::Real) = $Data.Flat($field)

        function (::$_Data)($field)
            $field = @tographdata $field {Vector, Map}{Float64}
            if $field isa Vector
                $Data.Raw($field)
            else
                $Data.Map($field)
            end
        end

        # ==================================================================================
        # Queries.

        module $M # (to not pollute invokation scope)
        import EcologicalNetworksDynamics: Views, @method, Internal, Model

        $get_data(::Internal, m::Model) = Views.nodes_view(m, $s_class, $s_data)
        @method $m $M.$get_data read_as($data) depends($Data)

        end

        # ==================================================================================
        # Display.
        function $Framework.shortline(io::IO, model::Model, ::$_Data)
            network = $EN.value(model)
            class = $N.class(network, $s_class)
            entry = class.data[$s_data]
            $N.read(entry) do data
                print(io, "$($Data): [$(join_elided(data, ", "))]")
            end
        end

    end
    mod.eval.(xp.args)
end
