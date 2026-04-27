# Typical setup for a component bringing a new field
# to a network *sub*class, with a `sparse` logic.
# It gets its own blueprints types,
# but substantial parts of their behaviour
# is inherited from the regular abstract functions for root node fields.

function define_sparse_node_field_component(
    mod::Module,
    d::SparseNodeField;
    blueprints = [],
    requires = [],
    # The component that defines the class. Defaults to a component with this class name.
    ClassComponent = nothing,
)
    nc = NodeClass(d)
    Class = D.CamelCaseSingular(nc)
    class, field = D.content(d)
    value, values, Value, Values, short = D.name_variants(d)
    T = D.type(d)
    Value_ = Symbol(Value, :_)
    _Value = Symbol(:_, Value) # Component type name.

    # ======================================================================================
    # Blueprints for the component.

    ClassComponent = isnothing(ClassComponent) ? mod.eval(Class) : ClassComponent
    bpmod =
        mod.eval.(
            (
                quote
                    module $Value_
                    import EcologicalNetworksDynamics:
                        EN, Networks, N, Framework, F, NF, D, Blueprint, Brought, Views
                    using SparseArrays
                    const Class = $ClassComponent
                    const _Class = typeof(Class)
                    const d = $d
                    const (class, field) = D.content(d)
                    end
                end
            ).args
        ) |> last

    #---------------------------------------------------------------------------------------
    # From raw values: one per node in the subclass (=dense).
    bpmod.eval(
        quote
            mutable struct Raw <: Blueprint
                $field::Vector{$T}
                Raw($field) = new($construct_raw(d, $field))
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

    bpmod.eval(quote
        mutable struct Map <: Blueprint
            $field::EN.Map{$T}
            Map($field) = new($construct_map(d, $field))
        end
        NF.define_blueprint(Map, "[$class => $field] map")
        export Map
    end)

    #---------------------------------------------------------------------------------------
    # From a scalar broadcasted to all nodes in the subclass (if meaningful).
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
    requires = [ClassComponent, requires...]
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
# Only redefine parts that do not already work with regular NodeField.

function construct(d::SparseNodeField, Field::Component, input)
    T = D.type(d)
    tries = []
    if may_flat(d)
        push!(tries, T => v -> Field.Flat(v))
    end
    push!(tries, Vector{T} => v -> Field.Raw(v))
    push!(tries, Map{T} => m -> Field.Map(m))
    input_try(input, tries...)
end

function nodes_shortline(io::IO, model::Model, d::SparseNodeField)
    # Display it sparse within its parent class.
    T = D.type(d)
    c, f, p = D.content(d)
    Field = D.CamelCaseSingular(d)
    network = NF.network(model)
    n_parents = N.n_nodes(network, p)
    subclass = N.class(network, c)
    r = subclass.restriction
    entry = subclass.data[f]
    N.read(entry) do data
        sparse = N.expand(T, r, n_parents, data)
        print(io, "$Field: [$(EN.join_elided(sparse, ", "))]")
    end
end
