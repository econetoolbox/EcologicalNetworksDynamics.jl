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
            NF.data(bp::Raw) = bp.$short
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
            NF.data(bp::Map) = bp.$short
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

    cp = NF.eval(
        quote
            define_component(
                $(Meta.quot(Singular)),
                $mod;
                requires = ($Class, $(requires...)),
                blueprints = ($bpmod, $(blueprints...)),
            )
        end,
    )
    CP = typeof(cp)
    NF.eval(
        quote
            $D.component(::$_D) = $cp
            (::$CP)($short, args...; kwargs...) =
                NF.construct($d, $cp, $short, args...; kwargs...)
        end,
    )

    if may_flat(d)
        R = flat(d) # Receiver type.
        NF.eval(quote
            (::$CP)($short::$R) = $cp.Flat($short)
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
                const d, prop, CP = $d, $prop, $CP
                D.viewtype(::typeof(d)) = V.NodeFieldView
                get_value(::Network, md::Model) = V.field_view(d, md)
                NF.define_method(get_value; read_as = prop, depends = (CP,))
                if !D.readonly(d)
                    set_value!(::Network, md::Model, input) = NF.assign!(d, md, input)
                    NF.define_method(set_value!; write_as = prop, depends = (CP,))
                end
                end
            end
        ).args |> last,
    )

    # Display.
    NF.eval(
        quote
            F.shortline(io::IO, model::Model, ::$CP) = NF.nodes_shortline(io, model, $d)
        end,
    )

    (cp, CP)
end

# ==========================================================================================
# Specialization.

datatype(BP::Type{<:NodeFieldRawBlueprint}) = Vector{D.type(BP)}
datatype(BP::Type{<:NodeFieldMapBlueprint}) = Map{D.type(BP)}
datatype(BP::Type{<:NodeFieldFlatBlueprint}) = D.type(BP)

#-------------------------------------------------------------------------------------------
# Construct.

function construct(d::D.AbstractNodeField, Field::Component, input, args...; kwargs...)
    T = D.type(d)
    tries = (
        Vector{T} => x -> Field.Raw(x, args...; kwargs...),
        Map{T} => x -> Field.Map(x, args...; kwargs...),
    )
    if may_flat(d)
        tries = (T => x -> Field.Flat(x, args...; kwargs...), tries...) # (try flat first)
    end
    try
        try_convert(input, tries...)
    catch e
        e isa BlueprintError && rethrow(e)
        e isa LibError || rethrow(e)
        e = CheckError(e)
        e.d = d
        rethrow(e)
    end
end

# Allow passing values as separate arguments.
construct(BP::Type{<:Union{NodeFieldRawBlueprint,NodeFieldMapBlueprint}},
    first, second, rest...) = bp_construct(BP, (first, second, rest...))

#-------------------------------------------------------------------------------------------
# Intrinsic check.

# Default to checking every value independenly.
# (It has been checked that the compiler is eliding the whole loop
# in case `intrinsic_check` is defaulting to no-op.)
function intrinsic_check(
    d::D.AbstractNodeField,
    data::Union{Vector,Map},
    checkref = ref -> (),
)
    for (uref, x) in pairs(data)
        urefguard(uref) do
            checkref(uref)
            intrinsic_check(d, x, uref)
        end
    end
    data
end

# In addition to every value being checked,
# indices-maps also must be *dense* on construction.
function intrinsic_check(BP::Type{<:NodeFieldMapBlueprint}, map::Map{<:Any,Int})
    d = dispatcher(BP)
    n = length(map)
    intrinsic_check(
        d,
        map,
        ref -> begin
            ref <= n && return
            n, s, are = nsa(n)
            checkerr(
                ref,
                "There $are only $n value$s in the given map \
                 so no index can be $ref.")
        end,
    )
end

# Extension point.
intrinsic_check(d::D.AbstractNodeField, x, ::Ref) = intrinsic_check(d, x)

#-------------------------------------------------------------------------------------------
# Early check.

# Hmpf.. unfortunate necessary wiring? :\
early_check(BP::Type{<:NodeFieldMapBlueprint}, map::Map{<:Any,Int}) =
    intrinsic_check(BP, map)

#-------------------------------------------------------------------------------------------
# Late check.

# Extension point, checking individual values against the model.
# Raise simple `checkerr` on failure, the report will be upgraded anyway.
late_check(::Model, ::D.AbstractNodeField, x, ::Int, ::Symbol) = x

# Raw.
function late_check(md::Model, bp::NodeFieldRawBlueprint, vec::Vector)
    # Check plain number of provided values.
    d, nw = dispatcher(bp), N.network(md)
    cl = D.class(d)
    exp, act = N.n_nodes(nw, cl), length(vec)
    exp == act || checkerr(vec,
        "Wrong number of values received: expected $exp, got $cyan$act$reset.")
    # Then check values one by one.
    labels = N.node_labels(nw, cl)
    map(enumerate(zip(labels, vec))) do (i, (label, x))
        try
            late_check(md, d, x, i, label)
        catch e
            e isa LibError || rethrow(e)
            if !(e isa CheckError)
                e = CheckError(e)
            end
            e.mref = (i, label)
            rethrow(e)
        end
    end
end

# Map (labels).
function late_check(md::Model, bp::NodeFieldMapBlueprint, map::Map{<:Any,Symbol})
    # Check references first.
    late_check_refs(md, dispatcher(bp), map; must_be_complete = true)
    # Then reorder and check values one by one.
    d = dispatcher(bp)
    nw, c = N.network(md), D.class(d)
    ix = N.class(nw, c).index
    [map[l] for l in ix.reverse]
end

# Map (indices).
function late_check(md::Model, bp::NodeFieldMapBlueprint, map::Map{<:Any,Int})
    late_check_refs(md, dispatcher(bp), map; must_be_complete = true)
    # Then reorder and check values one by one.
    d = dispatcher(bp)
    nw, c = N.network(md), D.class(d)
    cl = N.class(nw, c)
    n = length(cl)
    [map[i] for i in 1:n]
end

# Check without producing returned data.
function late_check_refs(
    md::Model,
    d::D.AbstractNodeField,
    map::Map{<:Any,Symbol};
    must_be_complete = true, # Lower for assignment.
)
    nw = N.network(md)
    c = D.class(d)
    labels = N.node_labels(nw, c)
    exp = Set(labels)
    act = Set(keys(map))
    render(set) = join_elided(
        sort!(collect(I.map(ref -> "$green$(repr(ref))$reset", set))),
        ", ", " and "; repr = false)
    if must_be_complete
        miss = setdiff(exp, act)
        isempty(miss) ||
            checkerr(map, "Missing: no value provided for $(render(miss)).")
    end
    unexp = setdiff(act, exp)
    if !isempty(unexp)
        a, s = length(unexp) == 1 ? (" a", "") : ("", "s")
        checkerr(map, "Not$a $cyan$(repr(c))$reset name$s: $(render(unexp)).")
    end
    nothing
end

function late_check_refs(
    md::Model,
    d::D.AbstractNodeField,
    map::Map{<:Any,Int};
    must_be_complete = true,
)
    nw = N.network(md)
    c = D.class(d)
    n = N.n_nodes(nw, c)
    miss = Int[]
    for exp in 1:n
        haskey(map, exp) && continue
        push!(miss, exp)
    end
    render(set) = join_elided(
        I.map(ref -> "$green$(repr(ref))$reset", set),
        ", ", " and "; repr = false)
    if must_be_complete && !isempty(miss)
        s = length(miss) == 1 ? "" : "s"
        checkerr(map, "Missing: no value provided for node$s $(render(miss)).")
    end
    unexp = miss
    for act in keys(map)
        act in 1:n && continue
        push!(unexp, act)
    end
    if !isempty(unexp)
        indices, s = length(unexp) == 1 ? ("index", "") : ("indices", "s")
        checkerr(
            map,
            "Invalid $indices for class $(repr(c)) with $n node$s: $(render(unexp)).",
        )
    end
    nothing
end

#-------------------------------------------------------------------------------------------
# Implied class.

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
# Expand.

# Flat.
function expand!(md::Model, bp::NodeFieldFlatBlueprint, low)
    d = dispatcher(bp)
    nw, cl = N.network(md), D.class(d)
    n = N.n_nodes(nw, cl)
    vec = fill(low, n)
    expand!(md, d, vec)
end

function expand!(md::Model, d::D.AbstractNodeField, low::Vector)
    # Even with the .Raw blueprint,
    # late-checking guarantees that lowered data is fresh = not aliased by user.
    nw, (c, f) = (N.network(md), D.content(d))
    class = N.class(nw, c)
    N.add_field!(class, f, low)
end

#-------------------------------------------------------------------------------------------
# Obtain.

function obtain(v::V.NodeFieldView, q::Ref)
    i = N.to_index(N.class(v).index, q)
    read(N.entry(v)) do data
        data[i]
    end
end

#-------------------------------------------------------------------------------------------
# Reassign (mutate to whole data).

function mutate!(md::Model, d::D.AbstractNodeField, ::_WholeData, raw) # (or flat)
    entry = N.entry(md, d)
    N.mutate!(entry) do nodes
        nodes .= raw
    end
end

function mutate!(md::Model, d::D.AbstractNodeField, ::_WholeData, map::Map)
    ix = N.class(md, d).index
    entry = N.entry(md, d)
    N.mutate!(entry) do nodes
        for (label, x) in map
            i = N.to_index(ix, label)
            nodes[i] = x
        end
    end
end

#-------------------------------------------------------------------------------------------
# Finer-grained mutation.

function mutate!(md::Model, d::D.AbstractNodeField, (i,)::Tuple{Int}, x)
    entry = N.entry(md, d)
    N.mutate!(entry) do nodes
        nodes[i] = x
    end
end

function mutate!(md::Model, d::D.AbstractNodeField, (l,)::Tuple{Symbol}, x)
    ix = N.class(md, d).index
    i = N.to_index(ix, l)
    mutate!(md, d, (i,), x)
end

#-------------------------------------------------------------------------------------------
# Display.

function nodes_shortline(io::IO, md::Model, d::D.NodeField)
    cc, fc, rs = F.component_color, F.field_color, reset
    Field = D.CamelCaseSingular(d)
    c, f = D.content(d)
    nw = N.network(md)
    cl = N.class(nw, c)
    entry = cl.data[f]
    N.read(entry) do data
        print(io, "$cc$Field$rs: $fc[$(join_elided(data, ", "))]$rs")
    end
end
