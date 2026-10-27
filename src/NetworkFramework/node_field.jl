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
                    set_value!(::Network, md::Model, input) =
                        NF.mut_set!(md, d, NF.WholeData, input)
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
# Early check.

# Default to checking every value independenly.
# (It has been checked that the compiler is eliding the whole loop
# in case `early_check` is defaulting to no-op.)
function early_check(
    d::D.AbstractNodeField,
    data::Union{Vector,Map},
    checkref = ref -> (),
)
    for (uref, x) in pairs(data)
        urefguard(uref) do
            checkref(uref)
            early_check(d, x, uref)
        end
    end
    data
end

# In addition to every value being checked,
# indices-maps also must be *dense* on construction.
function bp_early_check(d::D.AbstractNodeField, map::Map{<:Any,Int})
    n = length(map)
    early_check(d, map,
        ref -> begin
            ref <= n && return
            n, s, are = nsa(n)
            checkerr(
                ref,
                "There $are only $n value$s in the given map \
                 so no index can be $ref.")
        end)
end

# Extension point.
early_check(d::D.AbstractNodeField, x, ::Ref) = early_check(d, x)

#-------------------------------------------------------------------------------------------
# Late check, when obtaining vectors.

# Extension point, checking individual values against the model.
# Raise simple `checkerr` on failure, the report will be upgraded anyway.
late_check(::Model, ::D.AbstractNodeField, x, ::Int, ::Symbol) = x

# Guarding the above.
_late_check(md::Model, d::D.AbstractNodeField, x, i::Int, l::Symbol) =
    try
        late_check(md, d, x, i, l)
    catch e
        e isa LibError || rethrow(e)
        if !(e isa CheckError)
            e = CheckError(e)
        end
        e.mref = (i, l)
        rethrow(e)
    end

# When obtaining a vector, lower to a vector.
function late_check(md::Model, d::D.NodeField, vec::Vector)
    # Check plain number of provided values.
    cl = N.class(md, d)
    exp, act = N.n_nodes(cl), length(vec)
    exp == act || checkerr(vec,
        "Wrong number of values received: expected $exp, got $cyan$act$reset.")
    # Then check values one by one.
    labels = N.node_labels(cl)
    map(enumerate(zip(labels, vec))) do (i, (label, x))
        _late_check(md, d, x, i, label)
    end
end

#-------------------------------------------------------------------------------------------
# Late check, when obtaining maps.

"Check (only) label references against the model."
function late_check_refs(
    md::Model,
    d::D.AbstractNodeField,
    map::Map{<:Any,Symbol};
    complete = true,
)
    nw = N.network(md)
    c = D.class(d)
    labels = N.node_labels(nw, c)
    exp = Set(labels)
    act = Set(keys(map))
    render(set) = join_elided(
        sort!(collect(I.map(ref -> "$green$(repr(ref))$reset", set))),
        ", ", " and "; repr = false)
    if complete
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

"Check (only) index references against the model."
function late_check_refs(
    md::Model,
    d::D.AbstractNodeField,
    map::Map{<:Any,Int};
    complete = true,
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
    unexp = if isempty(miss)
        miss
    elseif complete
        s = length(miss) == 1 ? "" : "s"
        checkerr(map, "Missing: no value provided for node$s $(render(miss)).")
    else
        empty!(miss)
    end
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

# When obtaining a map (expansion pipeline: all values required), lower to a vector.
function bp_late_check(md::Model, d::D.NodeField, map::Map)
    late_check_refs(md, d, map; complete = true)
    ix = N.class(md, d).index
    T = D.type(d)
    res = sizehint!(T[], length(map))
    for (i, l) in enumerate(ix.reverse) # (reorder values)
        early = get_from_map(map, i, l)
        late = _late_check(md, d, early, i, l)
        push!(res, late)
    end
    res
end
get_from_map(map::Map{<:Any,Int}, i::Int, ::Symbol) = map[i]
get_from_map(map::Map{<:Any,Symbol}, ::Int, l::Symbol) = map[l]

# When obtaining a map (mutation pipeline: not all values are required): lower to a map.
function mut_late_check(md::Model, d::D.NodeField, map::Map)
    late_check_refs(md, d, map; complete = false)
    late_check_map_values(md, d, map)
end

# Just read to check on index-maps.
function late_check_map_values(md::Model, d::D.NodeField, map::Map{<:Any,Int})
    ix = N.class(md, d).index
    for (i, early) in pairs(map)
        l = N.to_label(ix, i)
        _late_check(md, d, early, i, l)
    end
    map
end

# Convert and read for symbol-maps.
function late_check_map_values(md::Model, d::D.NodeField, map::Map{<:Any,Symbol})
    ix = N.class(md, d).index
    late_check_map_values(md, d,
        OrderedDict(N.to_index(ix, l) => x for (l, x) in pairs(map)))
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
function expand!(md::Model, d::D.AbstractNodeField, low)
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

function obtain(v::V.NodeFieldView, (q,)::Tuple{Ref})
    i = N.to_index(N.class(v).index, q)
    read(N.entry(v)) do data
        data[i]
    end
end

# ==========================================================================================
# Mutate.

#-------------------------------------------------------------------------------------------
# Converting RHS.

function convert(d::D.AbstractNodeField, input)
    T = D.type(d)
    try_convert(input, T, Vector{T}, Map{T})
end

#-------------------------------------------------------------------------------------------
# Targetting whole data the "reassign-like" way: `m.property = rhs`.

function mutate!(md::Model, d::D.AbstractNodeField, ::_WholeData, raw) # (vec or flat)
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
# Targetting individual node the `setindex!` way: `view[index] = rhs`.

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
