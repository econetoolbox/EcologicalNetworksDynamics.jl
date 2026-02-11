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
    # Data name and its class.
    class::Symbol,
    Class::Union{Symbol,Expr},
    data::Symbol,
    Data::Symbol;
    #---------------------------------------------------------------------------------------
    # Extension points.

    # Extend checks beyond the default ones.
    late_check = (; Raw = (raw, bp, model) -> nothing, Map = (raw, bp, model) -> nothing),

    # Code for extra blueprints, evaluated within the code generated here.
    Blueprints = nothing,

    # Extra requirements for the component.
    requires = (),

    # Raise to produce a 'Flat' blueprint
    # expanding the same scalar value to the whole class.
    # If raised, provide the argument type for component-call constructor.
    flat_blueprint = nothing,
)
    #---------------------------------------------------------------------------------------
    Data_ = Symbol(Data, :_) # Blueprints module name.
    _Data = Symbol(:_, Data) # Component type name.
    s_data, s_field, s_class = Meta.quot.((data, field, class)) # Symbol names.
    N = Networks
    # For queries.
    M = Symbol(Data, :Methods)
    m = :(mod($mod))
    get_data = Symbol(:get_, data)

    # ======================================================================================
    # Blueprints for the component.

    # Prepare dedicated blueprints module and populate namespace.
    blueprints =
        mod.eval.(
            (
                quote
                    module $Data_
                    import EcologicalNetworksDynamics:
                        Blueprint, Framework, Networks, GraphDataInputs, Views, @blueprint
                    using .Networks
                    using .Framework
                    using .GraphDataInputs
                    const F = Framework
                    const Class = $mod.$Class
                    const _Class = typeof(Class)
                    end
                end
            ).args
        ) |> last


    #---------------------------------------------------------------------------------------
    # From raw values.

    blueprints.eval(
        quote
            mutable struct Raw <: Blueprint
                $field::Vector{$T}
                $class::Brought(Class)
                Raw($field, $class = _Class) =
                    new(@tographdata($field, Vector{$T}), $class)
            end
            F.implied_blueprint_for(bp::Raw, ::_Class) = Class(length(bp.$field))
            @blueprint Raw "raw values"
            export Raw

            F.early_check(bp::Raw) = check_nodes(check, bp.$field)
            function check(value, ref = nothing)
                v = try
                    $check_value(value)
                catch e
                    e isa String || rethrow(e)
                    index = if isnothing(ref)
                        ""
                    else
                        "[$(join(repr.(ref), ", "))]"
                    end
                    checkfails("$e: $($s_field)$index = $(repr(value))")
                end
            end

            function F.late_check(raw, bp::Raw, model)
                (; $field) = bp
                S = n_nodes(raw, $s_class)
                @check_size $field S
                $(late_check.Raw)(raw, bp, model)
            end

            F.expand!(raw, bp::Raw) = expand_from_vector!(raw, bp.$field)
            expand_from_vector!(raw, vec) =
                add_field!(class(raw, $s_class), $s_data, check.(vec))
        end,
    )


    #---------------------------------------------------------------------------------------
    # From a node-indexed map.
    blueprints.eval(
        quote
            mutable struct Map <: Blueprint
                $field::@GraphData Map{$T}
                $class::Brought(Class)
                Map($field, sp = _Class) = new(@tographdata($field, Map{$T}), sp)
            end
            F.implied_blueprint_for(bp::Map, ::_Class) = Class(refspace(bp.$field))
            @blueprint Map "[$($s_class) => $($s_data)] map"
            export Map

            F.early_check(bp::Map) = check_nodes(check, bp.$field)
            function F.late_check(raw, bp::Map, model)
                (; $field) = bp
                index = model.$class._index
                @check_list_refs $field $s_class index dense
                $(late_check.Map)(raw, bp, model)
            end

            function F.expand!(raw, bp::Map, model)
                index = model.$class._index
                vec = to_dense_vector(bp.$field, index)
                expand_from_vector!(raw, vec)
            end
        end,
    )

    #---------------------------------------------------------------------------------------
    # From a scalar broadcasted to all nodes in the class (if meaningful).
    if !isnothing(flat_blueprint)
        blueprints.eval(
            quote
                mutable struct Flat <: Blueprint
                    $field::$T
                end
                @blueprint Flat "uniform value" depends(Class)
                F.early_check(bp::Flat) = check(bp.$field)
                F.expand!(raw, bp::Flat) =
                    expand_from_vector!(raw, to_size(bp.$field, n_nodes(raw, $s_class)))
                export Flat
            end,
        )
    end

    # Any extra blueprint code.
    blueprints.eval(Blueprints)

    # ======================================================================================
    # The component itself and generic blueprints constructors.

    mod.eval(
        quote
            @component $Data{Internal} requires($Class, $(requires...)) blueprints($Data_)
            export $Data

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
    mod.eval.(
        (
            quote
                module $M # (to not pollute invokation scope)
                import EcologicalNetworksDynamics: Views, @method, Internal, Model

                $get_data(::Internal, m::Model) = Views.nodes_view(m, $s_class, $s_data)
                @method $m $M.$get_data read_as($data) depends($Data)

                end
            end
        ).args,
    )

    # Specialize value checking prior to writing to views if any.

    # ======================================================================================
    # Display.
    mod.eval(quote
        function $Framework.shortline(io::IO, model::Model, ::$_Data)
            network = $EN.value(model)
            class = $N.class(network, $s_class)
            entry = class.data[$s_data]
            $N.read(entry) do data
                print(io, "$($Data): [$(join_elided(data, ", "))]")
            end
        end
    end)
end

# ==========================================================================================

