"""
Typical setup for a componing bringing a new field to a network *sub*class,
with a `sparse` logic.
It gets its own blueprints types, but substantial parts of their behaviour
is inherited from the regular abstract functions for root node fields.
"""
function define_subnode_field_component(
    mod::Module,
    d::D.SubnodeField;
    blueprints = [],
    requires = [],
)
    nc, _ = D.Class(d)
    Class = D.CamelCaseSingular(nc)
    class, field = D.content(d)
    value, values, Value, Values, short = D.name_variants(d)
    T = D.type(d)
    Value_ = Symbol(Value, :_)
    _Value = Symbol(:_, Value) # Component type name.

    # ======================================================================================
    # Blueprints for the component.

    ClassComponent = D.component(nc)
    bpmod = mod.eval(
        (
            quote
                module $Value_
                import EcologicalNetworksDynamics.NetworkFramework:
                    F, NF, D, @bp_construct, SparseVector
                using SparseArrays
                const Class, d, T = $ClassComponent, $d, $T
                const _Class = typeof(Class)
                const (class, field) = D.content(d)
                end
            end
        ).args |> last,
    )

    #---------------------------------------------------------------------------------------
    # From raw values: one per node in the subclass (=dense).

    bpmod.eval(quote
        mutable struct Raw <: NF.SubnodeFieldRawBlueprint
            $field::Vector{T}
            @bp_construct Raw
        end
        export Raw
        NF.register_blueprint(Raw, "raw values"; d)
    end)

    # TODO: from a sparse vector whose structure is assumed to match parent class?

    #---------------------------------------------------------------------------------------
    # From a node-indexed map (never including parent refs).

    bpmod.eval(quote
        mutable struct Map <: NF.SubnodeFieldMapBlueprint
            $field::NF.Map{$T}
            @bp_construct Map
        end
        export Map
        NF.register_blueprint(Map, "[$class => $field] map"; d)
    end)

    #---------------------------------------------------------------------------------------
    # From a scalar broadcasted to all nodes in the subclass (if meaningful).

    if may_flat(d)
        bpmod.eval(
            quote
                mutable struct Flat <: NF.SubnodeFieldFlatBlueprint
                    $field::$T
                    @bp_construct Flat
                end
                NF.register_blueprint(Flat, "uniform value"; d, depends = [Class])
                export Flat
            end,
        )
    end

    # ======================================================================================
    # The component itself and generic blueprints constructors.

    _D = typeof(d)
    requires = [ClassComponent, requires...]
    cp = mod.eval(
        quote
            NF.define_component(
                $(Meta.quot(Value)),
                $mod;
                requires = $requires,
                blueprints = [$bpmod, $(blueprints...)],
            )
        end,
    )
    CP = typeof(cp)
    mod.eval(
        quote
            $D.component(::$_D) = $cp
            (::$_Value)($field, args...; kwargs...) =
                NF.construct($d, $Value, $field, args...; kwargs...)
        end,
    )

    if may_flat(d)
        R = flat(d) # Receiver type.
        mod.eval(quote
            (::$_Value)($field::$R) = $cp.Flat($field)
        end)
    end

    # Queries.
    M = Symbol(Values, :_Methods)
    prop = [value]
    mod.eval(
        (
            quote
                module $M
                using EcologicalNetworksDynamics.NetworkFramework: V, NF, D, Network, Model
                const d, prop, CP = $d, $prop, $CP
                D.viewtype(::typeof(d)) = V.SubnodeFieldView
                get_value(::Network, md::Model) = V.field_view(d, md)
                NF.define_method(get_value; read_as = prop, depends = [CP])
                if !D.readonly(d)
                    set_value!(::Network, md::Model, input) =
                        NF.mut_set!(md, d, NF.WholeData, input)
                    NF.define_method(set_value!; write_as = prop, depends = [CP])
                end
                end
            end
        ).args |> last,
    )

    # Display.
    NF.eval(quote
        $F.shortline(io::IO, md::Model, ::$CP) = $NF.nodes_shortline(io, md, $d)
    end)

    (cp, CP)

end

# ==========================================================================================
# Only redefine parts that do not already work with regular NodeField.

#-------------------------------------------------------------------------------------------
# Obtain.
# The index is expected to stand within parent class.
# Yield zero when off-subclass.

function obtain(vw::V.SubnodeFieldView, (q,)::Tuple{Ref})
    i_parent = N.to_index(N.parent(vw).index, q)
    rs = N.class(vw).restriction
    T = eltype(vw)
    if i_parent in rs
        i_loc = N.tolocal(rs, i_parent)
        read(N.entry(vw)) do data
            data[i_loc]
        end
    else
        zero(T)
    end
end

# ==========================================================================================
# Mutate.
# The index is expected to stand within parent class.
# Ignore when off-subclass: rejected during late-check if nonzero.

mut_late_check(md::Model, d::D.SubnodeField, early) = late_check(md, d, early, N.parent)

function mut_late_check(md::Model, d::D.SubnodeField, (i,)::Tuple{Int}, x)
    rs = N.class(md, d).restriction
    if i in rs
        ix = N.parent(md, d).index
        l = N.to_label(ix, i)
        _late_check(md, d, x, (i, l))
    else
        T = D.type(d)
        x === zero(T) && return x
        c = D.snake_case_singular(first(D.Class(d)))
        checkerr(x, "Not a null value for a non-$green$c$reset.")
    end
end

function mutate!(md::Model, d::D.SubnodeField, ::_WholeData, raw)
    rs = N.class(md, d).restriction
    entry = N.entry(md, d)
    N.mutate!(entry) do nodes
        for (i_local, i_parent) in enumerate(N.indices(rs))
            nodes[i_local] = raw[i_parent]
        end
    end
end

function mutate!(md::Model, d::D.SubnodeField, ::_WholeData, map::Map)
    cl = N.class(md, d)
    entry = N.entry(md, d)
    N.mutate!(entry) do nodes
        for (label, x) in map
            i_parent = N.to_index(cl.index, label)
            i_local = N.tolocal(cl.restriction, i_parent)
            nodes[i_local] = x
        end
    end
end

function mutate!(md::Model, d::D.SubnodeField, (i_parent,)::Tuple{Int}, x)
    rs = N.class(md, d).restriction
    if i_parent in rs
        i_local = N.tolocal(rs, i_parent)
        entry = N.entry(md, d)
        N.mutate!(entry) do nodes
            nodes[i_local] = x
        end
    else
        T = D.type(d)
        zero(T)
    end
end

# ==========================================================================================
# Display.
# Sparse within its parent class.

function nodes_shortline(io::IO, md::Model, d::D.SubnodeField)
    cc, fc, rs = F.component_color, F.field_color, reset
    T = D.type(d)
    c, f, p = D.content(d)
    Field = D.CamelCaseSingular(d)
    nw = N.network(md)
    n_parents = N.n_nodes(nw, p)
    subclass = N.class(nw, c)
    r = subclass.restriction
    entry = subclass.data[f]
    N.read(entry) do data
        sparse = N.expand(T, r, n_parents, data)
        print(io, "$cc$Field$rs: $fc[$(join_elided(sparse, ", "))]$rs")
    end
end
