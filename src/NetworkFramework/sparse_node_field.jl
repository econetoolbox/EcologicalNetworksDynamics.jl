"""
Expand into a subclass field from a raw vector,
one element per node in the subclass.
"""
abstract type SubClassFieldRawBlueprint <: ClassFieldRawBlueprint end

"""
Expand into a subclass field from mapped values.
"""
abstract type SubClassFieldMapBlueprint <: ClassFieldMapBlueprint end

"""
Expand into a subclass field from a single value.
"""
abstract type SubClassFieldFlatBlueprint <: ClassFieldFlatBlueprint end

"""
Typical setup for a componing bringing a new field to a network *sub*class,
with a `sparse` logic.
It gets its own blueprints types, but substantial parts of their behaviour
is inherited from the regular abstract functions for root node fields.
"""
function define_sparse_node_field_component(
    mod::Module,
    d::SparseNodeField;
    blueprints = [],
    requires = [],
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

    ClassComponent = D.component(nc)
    bpmod = mod.eval((
        quote
            module $Value_
            import EcologicalNetworksDynamics: F, NF, D
            using SparseArrays
            const Class = $ClassComponent
            const _Class = typeof(Class)
            const d = $d
            const (class, field) = D.content(d)
            end
        end
    ).args |> last)

    #---------------------------------------------------------------------------------------
    # From raw values: one per node in the subclass (=dense).
    bpmod.eval(quote
        mutable struct Raw <: NF.SubClassFieldRawBlueprint
            $field::Vector{$T}
            Raw($field) = new(NF.construct(d, Raw, $field))
        end
        NF.data(bp::Raw) = bp.$field
        F.early_check(bp::Raw) = NF.early_check(d, bp)
        F.late_check(model, bp::Raw, data) = NF.late_check(d, model, bp, data)
        F.expand!(model, bp::Raw, data) = NF.expand!(d, model, bp, data)
        NF.define_blueprint(Raw, "raw values")
        export Raw
    end)

    #---------------------------------------------------------------------------------------
    # From a node-indexed map.

    bpmod.eval(quote
        mutable struct Map <: NF.SubClassFieldMapBlueprint
            $field::NF.Map{$T}
            Map($field) = new(NF.construct(d, Map, $field))
        end
        NF.data(bp::Map) = bp.$field
        F.early_check(bp::Map) = NF.early_check(d, bp)
        F.late_check(model, bp::Map, data) = NF.late_check(d, model, bp, data)
        F.expand!(model, bp::Map, data) = NF.expand!(d, model, bp, data)
        NF.define_blueprint(Map, "[$class => $field] map")
        export Map
    end)

    #---------------------------------------------------------------------------------------
    # From a scalar broadcasted to all nodes in the subclass (if meaningful).
    if may_flat(d)
        bpmod.eval(
            quote
                mutable struct Flat <: NF.SubClassFieldFlatBlueprint
                    $field::$T
                end
                NF.data(bp::Flat) = bp.$field
                F.early_check(bp::Flat) = NF.early_check(d, bp)
                F.late_check(model, bp::Flat, data) = NF.late_check(d, model, bp, data)
                F.expand!(model, bp::Flat, data) = NF.expand!(d, model, bp, data)
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
    mod.eval(
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
        ).args |> last,
    )

    # Display.
    mod.eval(quote
        $F.shortline(io::IO, model::Model, ::$C) = $nodes_shortline(io, model, $d)
    end)

    comp

end

# ==========================================================================================
# Only redefine parts that do not already work with regular NodeField.

# No need to bring the class (yet).
function construct(d::SparseNodeField, Field::Component, input)
    T = D.type(d)
    tries = []
    if may_flat(d)
        push!(tries, T => v -> Field.Flat(v))
    end
    push!(tries, Vector{T} => v -> Field.Raw(v))
    push!(tries, Map{T} => m -> Field.Map(m))
    try_convert(input, tries...)
end

# Display it sparse within its parent class.
function nodes_shortline(io::IO, model::Model, d::SparseNodeField)
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

# Check index references against *parent* class.
function late_check(
    d::SparseNodeField,
    model::Model,
    ::SubClassFieldMapBlueprint,
    map::Map{<:Any,Int},
)
    # Check indices first.
    network = NF.network(model)
    class = D.class(d)
    parent = D.parent(d)
    r = N.restriction(network, class)
    miss = Int[]
    for exp in N.indices(r)
        haskey(map, exp) && continue
        push!(miss, exp)
    end
    if !isempty(miss)
        miss = EN.join_elided(miss, ", ", " and ")
        s = length(miss) == 1 ? "" : "s"
        F.checkfails("Missing for $d, no value provided for $(repr(parent)) node$s $miss.")
    end
    unexp = miss
    for act in keys(map)
        act in r && continue
        push!(unexp, act)
    end
    if !isempty(unexp)
        unexp = EN.join_elided(unexp, ", ", " and ")
        indices = length(unexp) == 1 ? "index" : "indices"
        F.checkfails("Invalid $indices for $class within $parent: $unexp.")
    end
    # Then reorder values one by one into a vector.
    [check_with_ref(d, model, map[i], N.tolocal(i, r)) for i in N.indices(r)]
end
