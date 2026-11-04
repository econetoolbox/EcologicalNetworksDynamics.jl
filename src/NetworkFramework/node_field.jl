"""
Raise to produce a 'Flat' blueprint
expanding the same scalar value to the whole class or web,
and allow flattening assignment.
If raised, provide the argument type for component-call constructor.
"""
flat(d::D.AbstractField) = D.type(d)
may_flat(d::D.AbstractField) = !isnothing(flat(d))

"Expand to a class field."
abstract type NodeFieldBlueprint <: Blueprint end

"Expand to a class field from a vector of raw values."
abstract type NodeFieldRawBlueprint <: NodeFieldBlueprint end

"Expand to a class field from mapped values."
abstract type NodeFieldMapBlueprint <: NodeFieldBlueprint end

"Expand to a class field from a single value."
abstract type NodeFieldFlatBlueprint <: NodeFieldBlueprint end

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
                implied = [Class], # Infer number of class nodes from vector size.
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
                implied = [Class], # Infer class nodes from map keys.
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
                NF.register_blueprint(Flat, "uniform value"; d, depends = [Class])
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
                using EcologicalNetworksDynamics.NetworkFramework:
                    V, N, NF, D, Network, Model
                const d, prop, CP = $d, $prop, $CP
                D.viewtype(::typeof(d)) = V.NodeFieldView
                get_value(::Network, md::Model) = V.field_view(d, md)
                get_entry(::Network, md::Model) = N.entry(md, d)
                NF.define_method(get_value; read_as = prop, depends = [CP])
                NF.define_method(get_entry; read_as = Symbol.((:_,), prop), depends = [CP])
                if !D.readonly(d)
                    set_value!(::Network, md::Model, input) =
                        NF.mut_set!(md, d, NF.wholedata, input)
                    NF.define_method(set_value!; write_as = prop, depends = [CP])
                end
                end
            end
        ).args |> last,
    )

    # Display.
    NF.eval(
        quote
            F.shortline(io::IO, md::Model, ::$CP) = nodes_shortline(io, md, $d)
        end,
    )

    (cp, CP)
end

# ==========================================================================================
# Specialization.

#-------------------------------------------------------------------------------------------
# Construct.

function construct(d::D.NodeField, Field::Component, input, args...; kwargs...)
    T = D.type(d)
    tries = (
        Vector{T} => x -> Field.Raw(x, args...; kwargs...),
        Map{T} => x -> Field.Map(x, args...; kwargs...),
    )
    if may_flat(d)
        tries = (
            T => x -> Field.Flat(x, args...; kwargs...),
            tries...,
        )
    end
    try
        try_convert(input, tries...)
    catch e
        e isa BlueprintError && rethrow(e) # Thrown by underlying constructor: already ok.
        e isa LibError || rethrow(e) # Otherwise upgrade.
        e = CheckError(e)
        e.d = d
        rethrow(e)
    end
end

# Allow passing values as separate arguments.
construct(BP::Type{<:Union{NodeFieldRawBlueprint,NodeFieldMapBlueprint}},
    first, second, rest...) = construct(BP, (first, second, rest...))

#-------------------------------------------------------------------------------------------
# Implied class.

function implied(::D.NodeField, Class::Component, bp::NodeFieldRawBlueprint)
    raw = data(bp)
    n = length(raw)
    Class.Number(n)
end

implied(d::D.NodeField, Class::Component, bp::NodeFieldMapBlueprint) =
    implied(d, Class, data(bp)) # Dispatch to either symbol or integer refs.

function implied(::D.NodeField, Class::Component, map::Map{<:Any,Symbol})
    refs = NF.keys(map)
    Class.Names(collect(refs))
end

function implied(::D.NodeField, Class::Component, map::Map{<:Any,Int})
    n = length(map)
    Class.Number(n)
end

#-------------------------------------------------------------------------------------------
# Early check.

"""
Extension point per node value.
May return transformed/lowered value (*e.g.* MetabolicDict),
to be collected (`bp`, `mut`) or not (`cst`) depending on the pipeline.
"""
early_check(d::D.NodeField, x, ::Ref) = early_check(d, x)

# On construction, check all values without creating anything new.
# (It has been checked that the compiler is eliding the whole loop
#  in case `early_check` is defaulting to no-op.)
function cst_early_check(BP::Type{<:NodeFieldBlueprint}, data::Union{Vector,Map})
    d = dispatcher(BP)
    for (ref, x) in pairs(data)
        urefguard((ref,)) do
            check_dense_ref(BP, ref, data)
            early_check(d, x, ref)
        end
    end
    data
end

# On expansion, checked values (possibly lowered) are collected.
function bp_early_check(bp::Union{NodeFieldRawBlueprint,NodeFieldMapBlueprint})
    d, data = dispatcher(bp), NF.data(bp)
    early_lower(d, data) do ref, x
        urefguard((ref,)) do
            check_dense_ref(typeof(bp), ref, data)
            early_check(d, x, ref) # <- Lowering may happen here.
        end
    end
end

# On mutation, don't check for density.
mut_early_check(d::D.NodeField, data::Union{Vector,Map}) = early_lower(d, data) do ref, x
    urefguard((ref,)) do
        early_check(d, x, ref)
    end
end

# Index-maps need to be dense: they cannot be holed.
check_dense_ref(::Type{<:NodeFieldBlueprint}, ref, _) = ref
function check_dense_ref(::Type{<:NodeFieldBlueprint}, i::Int, map::Map{<:Any,Int})
    n = length(map)
    i <= n && return i
    n, s, are = nsa(n)
    checkerr(i, "There $are only $n value$s in the given map so no index can be $i.")
end

# "Lower" either means into a fresh vector or a fresh map.
# TODO: skip reallocation if the early_check extension point does not convert values?
early_lower(fn::Function, ::D.NodeField, vec::Vector) = [fn(i, x) for (i, x) in pairs(vec)]
function early_lower(fn::Function, ::D.NodeField, data::Map)
    M = typeof(data)
    res = M()
    for (ref, x) in pairs(data)
        res[ref] = fn(ref, x)
    end
    res
end

#-------------------------------------------------------------------------------------------
# Late check, when obtaining vectors.

# Extension point, checking individual values against the model,
# having both index and label model ref available.
# Raise simple `checkerr` on failure, the report will be upgraded anyway.
late_check(::Model, ::D.NodeField, x, ::MRef) = x

# Guard the above to upgrade exceptions.
_late_check(md::Model, d::D.NodeField, x, mref::MRef) =
    try
        late_check(md, d, x, mref)
    catch e
        e isa LibError || rethrow(e)
        if !(e isa CheckError)
            e = CheckError(e)
        end
        e.ref = ModelRef((mref,))
        rethrow(e)
    end

# Lower to a fresh vector while checking.
function late_check(md::Model, d::D.NodeField, vec::Vector)
    # Check plain number of provided values.
    cl = N.class(md, d)
    exp, act = length.((cl, vec))
    exp == act || checkerr(vec,
        "Wrong number of values received: expected $exp, got $cyan$act$reset.")
    # Then check values one by one.
    labels = N.node_labels(cl)
    map(enumerate(zip(labels, vec))) do (i, (label, x))
        _late_check(md, d, x, (i, label))
    end
end

#-------------------------------------------------------------------------------------------
# Late check, when obtaining maps.

"Check (only) label references against the model."
function late_check_refs(md::Model, d::D.NodeField, map::Map{<:Any,Symbol}; complete = true)
    ix = N.class(md, d).index
    labels = N.labels(ix)
    exp = Set(labels)
    act = Set(keys(map))
    render(set) = join_elided(sort!(collect(set)), ", ", " and "; coleach = cyan)
    if complete
        miss = setdiff(exp, act)
        isempty(miss) ||
            checkerr(map, "Missing: no value provided for $(render(miss)).")
    end
    unexp = setdiff(act, exp)
    if !isempty(unexp)
        a, s, sn =
            length(unexp) == 1 ?
            (" a", "", D.snake_case_singular) :
            ("", "s", D.snake_case_plural)
        c = sn(first(D.Class(d)))
        checkerr(map, "Not$a $green$c$reset name$s: $(render(unexp)).")
    end
    nothing
end

"Check (only) index references against the model."
function late_check_refs(md::Model, d::D.NodeField, map::Map{<:Any,Int}; complete = true)
    rs = N.class(md, d).restriction
    n = length(rs)
    miss = Int[]
    for exp in N.indices(rs)
        haskey(map, exp) && continue
        push!(miss, exp)
    end
    render(set) = join_elided(set, ", ", " and "; coleach = green)
    unexp = if isempty(miss)
        miss
    elseif complete
        s = length(miss) == 1 ? "" : "s"
        checkerr(map, "Missing: no value provided for node$s $(render(miss)).")
    else
        empty!(miss)
    end
    for act in keys(map)
        act in rs && continue
        push!(unexp, act)
    end
    if !isempty(unexp)
        indices, s = length(unexp) == 1 ? ("index", "") : ("indices", "s")
        c = D.class(d)
        checkerr(
            map,
            "Invalid $indices for class $(repr(c)) with $n node$s: $(render(unexp)).",
        )
    end
    nothing
end

# When obtaining a map (expansion pipeline: all values required), lower to a vector.
function bp_late_check(md::Model, bp::NodeFieldMapBlueprint, map::Map)
    d = dispatcher(bp)
    late_check_refs(md, d, map; complete = true)
    ix = N.class(md, d).index
    rs = N.class(md, d).restriction
    T = D.type(d)
    res = sizehint!(T[], length(map))
    for (i, parent_i) in enumerate(N.indices(rs)) # (reorder values)
        l = N.to_label(ix, i)
        early = get_from_map(map, parent_i, l)
        late = _late_check(md, d, early, (parent_i, l))
        push!(res, late)
    end
    res
end
get_from_map(map::Map{<:Any,Int}, i::Int, ::Symbol) = map[i]
get_from_map(map::Map{<:Any,Symbol}, ::Int, l::Symbol) = map[l]

#-------------------------------------------------------------------------------------------
# Late check, on mutation pipeline.

function mut_late_check(md::Model, d::D.NodeField, (i,)::Tuple{Int}, x)
    ix = N.class(md, d).index
    l = N.to_label(ix, i)
    _late_check(md, d, x, (i, l))
end

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
        _late_check(md, d, early, (i, l))
    end
    map
end

# Read and convert for symbol-maps.
function late_check_map_values(md::Model, d::D.NodeField, map::Map{<:Any,Symbol})
    ix = N.class(md, d).index
    T = valtype(map)
    res = Map{T,Int}()
    for (l, early) in pairs(map)
        i = N.to_index(ix, l)
        late = _late_check(md, d, early, (i, l))
        res[i] = late
    end
    res
end

#-------------------------------------------------------------------------------------------
# Expand.

# Raw.
function expand!(md::Model, d::D.NodeField, vec::Vector)
    # Even with the .Raw blueprint,
    # early+late-checking guarantee that lowered data is fresh = not aliased by user.
    cl, f = N.class(md, d), D.field(d)
    N.add_field!(cl, f, vec)
end

# Map.
function expand!(md::Model, d::D.NodeField, map::Map)
    # Reorder into the final vector.
    R = reftype(map)
    ix = N.class(md, d).index
    vec = [map[ref] for ref in N.ordered(R, ix)] # (guaranteed without holes on `bp`)
    expand!(md, d, vec)
end

# Flat.
function expand!(md::Model, d::D.NodeField, flat)
    n = N.class(md, d) |> N.n_nodes
    vec = fill(flat, n)
    expand!(md, d, vec)
end

#-------------------------------------------------------------------------------------------
# Obtain.

function obtain(vw::V.NodeFieldView, (q,)::Tuple{Ref})
    i = N.to_index(N.class(vw).index, q)
    read(N.entry(vw)) do data
        data[i]
    end
end

# ==========================================================================================
# Mutate.

#-------------------------------------------------------------------------------------------
# Converting RHS.

function convert(d::D.NodeField, input)
    T = D.type(d)
    try_convert(input, T, Vector{T}, Map{T})
end

#-------------------------------------------------------------------------------------------
# Targetting whole data the "reassign-like" way: `m.property = rhs`.

function mutate!(md::Model, d::D.NodeField, ::WholeData, raw) # (vec or flat)
    N.mutate!(N.entry(md, d)) do nodes
        nodes .= raw
    end
end

function mutate!(md::Model, d::D.NodeField, ::WholeData, map::Map)
    ix = N.class(md, d).index
    N.mutate!(N.entry(md, d)) do nodes
        for (label, x) in map
            i = N.to_index(ix, label)
            nodes[i] = x
        end
    end
end

#-------------------------------------------------------------------------------------------
# Targetting individual node the `setindex!` way: `view[index] = rhs`.

function mutate!(md::Model, d::D.NodeField, (i,)::Tuple{Int}, x)
    entry = N.entry(md, d)
    N.mutate!(entry) do nodes
        nodes[i] = x
    end
end

function mutate!(md::Model, d::D.NodeField, (l,)::Tuple{Symbol}, x)
    ix = N.class(md, d).index
    i = N.to_index(ix, l)
    mutate!(md, d, (i,), x)
end

# ==========================================================================================
# Display.

function nodes_shortline(io::IO, md::Model, d::D.NodeField)
    cc, fc, rs = F.component_color, F.field_color, reset
    Field = D.CamelCaseSingular(d)
    N.read(N.entry(md, d)) do data
        dat = join_elided(data, ", "; coleach = fc)
        print(io, "$cc$Field$rs: [$(dat)]")
    end
end
