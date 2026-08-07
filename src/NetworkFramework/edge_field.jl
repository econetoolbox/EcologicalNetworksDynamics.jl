"""
Expand to a web field from a vector of raw values.
"""
abstract type EdgeFieldRawBlueprint <: Blueprint end

"""
Expand to a web field from a matrix.
"""
abstract type EdgeFieldMatrixBlueprint <: Blueprint end

"""
Expand to a web field from an adjacency list.
"""
abstract type EdgeFieldAdjacencyBlueprint <: Blueprint end

"""
Expand to a web field from a single value.
"""
abstract type EdgeFieldFlatBlueprint <: Blueprint end

"""
Typical setup for a component bringing a new web field to the network.
"""
function define_reflexive_web_field_component(
    mod::Module,
    d::D.EdgeField;
    blueprints = [], # Extra blueprints for the component.
    requires = [], # Extra requirements for the component.
)
    # Implementation mostly adapted from web.jl and nodes.jl.
    # TODO: how much of it could be factored? There is much duplication in here.

    # TODO: have it generic over D.is_sparse(d) the day it's required.

    ew = D.Web(d)
    Web = D.CamelCase(ew)
    web, field = D.content(d)
    src, tgt = D.sourcename(ew), D.targetname(ew)
    value, values, Value, Values, short = D.name_variants(d)
    T = D.type(d)
    Value_ = Symbol(Value, :_) # Blueprints module name.
    _Value = Symbol(:_, Value) # Component type name.

    # ======================================================================================
    # Blueprints for the component.

    bpmod = mod.eval((
        quote
            module $Value_
            import EcologicalNetworksDynamics: F, NF, D
            const ew = $ew
            const Web = D.component(ew)
            const _Web = typeof(Web)
            const d = $d
            const T = $T
            end
        end
    ).args |> last)

    #---------------------------------------------------------------------------------------
    # From raw values.

    bpmod.eval(quote
        mutable struct Raw <: NF.EdgeFieldRawBlueprint
            $short::Vector{T}
            Raw($short) = new(NF.construct(d, Raw, $short))
        end
        NF.data(bp::Raw) = bp.$short
        F.early_check(bp::Raw) = NF._early_check(d, bp)
        F.late_check(model, bp::Raw, data) = NF.late_check(d, model, bp, data)
        F.expand!(model, bp::Raw, data) = NF.expand!(d, model, bp, data)
        NF.define_blueprint(Raw, "raw values"; depends = [Web])
        export Raw
    end)

    #---------------------------------------------------------------------------------------
    # From a matrix.

    sparse = D.is_sparse(d)
    M = sparse ? SparseMatrix : Matrix
    bpmod.eval(
        quote
            mutable struct Matrix <: NF.EdgeFieldMatrixBlueprint
                $short::$M{T}
                Matrix($short) = new(NF.construct(d, Matrix, $short))
            end
            NF.data(bp::Matrix) = bp.$short
            F.implied(bp::Matrix) = (Web,)
            F.implied_blueprint_for(bp::Matrix, ::Type{_Web}) = NF.implied_web(d, Web, bp)
            F.early_check(bp::Matrix) = NF._early_check(d, bp)
            F.late_check(model, bp::Matrix, data) = NF.late_check(d, model, bp, data)
            F.expand!(model, bp::Matrix, data) = NF.expand!(d, model, bp, data)
            NF.define_blueprint(
                Matrix,
                $"a $(sparse ? "sparse " : "")matrix";
                depends = [Web],
            )
            export Matrix
        end,
    )

    #---------------------------------------------------------------------------------------
    # From an adjacency list.

    bpmod.eval(
        quote
            mutable struct Adjacency <: NF.EdgeFieldAdjacencyBlueprint
                $short::NF.Adjacency{T}
                Adjacency($short) = new(NF.construct(d, Adjacency, $short))
            end
            NF.data(bp::Adjacency) = bp.$short
            F.implied(bp::Adjacency) = (Web,)
            F.implied_blueprint_for(bp::Adjacency, ::Type{_Web}) =
                NF.implied_web(d, Web, bp)
            F.early_check(bp::Adjacency) = NF._early_check(d, bp)
            F.late_check(model, bp::Adjacency, data) = NF.late_check(d, model, bp, data)
            F.expand!(model, bp::Adjacency, data) = NF.expand!(d, model, bp, data)
            NF.define_blueprint(
                Adjacency,
                $"[$src => [$tgt => $field]] adjacency list";
                depends = [Web],
            )
            export Adjacency
        end,
    )

    #---------------------------------------------------------------------------------------
    # From a scalar broadcasted to all nodes in the web (if meaningful).

    if may_flat(d)
        bpmod.eval(
            quote
                mutable struct Flat <: NF.EdgeFieldFlatBlueprint
                    $short::T
                    Flat($short) = new(NF.construct(d, Flat, $short))
                end
                NF.data(bp::Flat) = bp.$short
                F.early_check(bp::Flat) = NF._early_check(d, bp)
                F.late_check(model, bp::Flat, data) = NF.late_check(d, model, bp, data)
                F.expand!(model, bp::Flat, data) = NF.expand!(d, model, bp, data)
                NF.define_blueprint(Flat, "uniform value"; depends = [Web])
                export Flat
            end,
        )
    end

    # ======================================================================================
    # The component itself and generic blueprints constructors.

    DT = typeof(d)
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
            (::$_Value)($short, args...; kwargs...) =
                $construct($d, $Value, $short, args...; kwargs...)
        end,
    )

    if may_flat(d)
        R = flat(d) # Receiver type.
        mod.eval(quote
            (::$_Value)($short::$R) = $Value.Flat($short)
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
                D.viewtype(::typeof(d)) = V.EdgeFieldView
                get_value(::Network, m::Model) = V.data_view(d, m)
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
    mod.eval(
        quote
            $F.shortline(io::IO, model::Model, ::$C) = $NF.edges_shortline(io, model, $d)
        end,
    )

    comp

end

# ==========================================================================================
# Extracted logic + extension points.
# Mostly inspired from node field.

#-------------------------------------------------------------------------------------------
# Contextless check.

check(d::D.EdgeField, value) = inputconvert(D.type(d), value)

const EdgeIndex = Tuple{Int,Int}
const EdgeLabel = Tuple{Symbol,Symbol}

check_with_ref(d::D.EdgeField, value, (i, j)::EdgeIndex) =
    try
        check(d, value)
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "On edge [$i, $j]")
    end
check_with_ref(d::D.EdgeField, value, (a, b)::EdgeLabel) =
    try
        check(d, value)
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "On edge $(repr(a)) => $(repr(b))")
    end
# Useful when constructing from raw values because edge indices are unknown yet.
check_with_raw_ref(d::D.EdgeField, value, i::Int) =
    try
        check(d, value)
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "At raw edge value [$i]")
    end

#-------------------------------------------------------------------------------------------
# Model-aware checks.

function check_with_ref(
    d::D.EdgeField,
    against::Model,
    value,
    i::EdgeIndex,
    l::EdgeLabel,
    # Provide if available and useful as context (for Raw).
    raw_i::Option{Int} = nothing,
)
    try
        value = check(d, value)
        check(d, against, value, i, l)
    catch e
        e isa F.InputError || rethrow(e)
        i, j = i
        a, b = l
        raw = isnothing(raw_i) ? "" : " ($raw_i)"
        with_context!(e, "On edge$raw $(repr(a)) => $(repr(b)) ([$i, $j])")
    end
end

# Extract indexes for both incident classes.
function indexes(d::D.EdgeField, network::Network)
    web = D.web(d)
    N.index.(network, D.sidenames(web))
end

# Infer any reference type from the other one.
function check_with_ref(d::D.EdgeField, against, value, (i, j)::EdgeIndex)
    model = get_model(against)
    network = NF.network(model)
    src, tgt = indexes(d, network)
    (a, b) = N.to_label.((src, tgt), (i, j))
    check_with_ref(d, model, value, (i, j), (a, b))
end
function check_with_ref(d::D.EdgeField, against, value, (a, b)::EdgeLabel)
    model = get_model(against)
    network = NF.network(model)
    src, tgt = indexes(d, network)
    (i, j) = N.to_index.((src, tgt), (a, b))
    check_with_ref(d, model, value, (i, j), (a, b))
end

#-------------------------------------------------------------------------------------------
# Construct.

# From raw edges.
function construct(d::D.EdgeField, ::Type{<:EdgeFieldRawBlueprint}, raw)
    T = D.type(d)
    try
        v = inputconvert(Vector{T}, raw)
        for (i, value) in enumerate(v)
            check_with_raw_ref(d, value, i)
        end
        v
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "When constructing $d from raw values")
    end
end

# From matrix.
function construct(d::D.EdgeField, ::Type{<:EdgeFieldMatrixBlueprint}, raw)
    T = D.type(d)
    M = D.is_sparse(d) ? SparseMatrix : Matrix
    try
        mat = inputconvert(M{T}, raw)
        checkmat(d, mat) # Specialized impl for sparse matrices.
        mat
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "When constructing $d from a matrix")
    end
end

function checkmat(d::D.EdgeField, mat::Matrix)
    m, n = size(mat)
    for i in 1:m, j in 1:n
        value = mat[i, j]
        check_with_ref(d, value, (i, j))
    end
end

function checkmat(d::D.EdgeField, mat::SparseMatrix)
    is, js, vals = findnz(mat)
    for (i, j, value) in zip(is, js, vals)
        check_with_ref(d, value, (i, j))
    end
end

# From adjacency lists.
function construct(d::D.EdgeField, ::Type{<:EdgeFieldAdjacencyBlueprint}, raw)
    T = D.type(d)
    try
        adj = inputconvert(Adjacency{T}, raw)
        for (i, j, value) in NF.iter(adj)
            check_with_ref(d, value, (i, j))
        end
        adj
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "When constructing $d from an adjacency list")
    end
end

# From flat scalar.
function construct(d::D.EdgeField, ::Type{<:EdgeFieldFlatBlueprint}, flat)
    T = D.type(d)
    try
        val = inputconvert(T, flat)
        check(d, val)
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "When constructing $d from a flat value")
    end
end

function construct(d::D.EdgeField, Field::Component, input; _...)
    parsed = parse(d, input)
    construct_from_parsed(d, Field, parsed)
end

construct_from_parsed(::D.EdgeField, Field::Component, raw::Vector) = Field.Raw(raw)
construct_from_parsed(::D.EdgeField, Field::Component, raw::AbstractMatrix) =
    Field.Matrix(raw)
construct_from_parsed(::D.EdgeField, Field::Component, raw::Adjacency) =
    Field.Adjacency(raw)
construct_from_parsed(::D.EdgeField, Field::Component, scalar) = Field.Flat(scalar)

function parse(d::D.EdgeField, input)
    T = D.type(d)
    tries = []
    if may_flat(d)
        push!(tries, T)
    end
    push!(tries, Vector{T})
    M = D.is_sparse(d) ? SparseMatrix : Matrix
    push!(tries, M{T})
    push!(tries, Adjacency{T})
    try_convert(input, tries...)
end

#-------------------------------------------------------------------------------------------
# Early check (dispatched from the generic method in `node_field.jl`).

# Raw.
function early_check(d::D.EdgeField, vec::Vector)
    T = eltype(vec)
    data = T[]
    sizehint!(data, length(vec))
    for (i, value) in enumerate(vec)
        value = check_with_raw_ref(d, value, i)
        push!(data, value)
    end
    data
end

# Matrix: construct a raw repr but also pass the original matrix to late_check.
# TODO: maybe cleanup internals conversions to `raw` because it's actually done here?
function early_check(d::D.EdgeField, mat::AbstractMatrix)
    D.is_symmetric(D.Web(d)) && return early_check_symmetric(d, mat)
    T = eltype(mat)
    raw = T[]
    sizehint!(raw, n_edges(mat))
    for (i, j, v) in edges_values(mat)
        value = check_with_ref(d, v, (i, j))
        push!(raw, value)
    end
    (raw, mat)
end

# Enforce that matrices be symmetric for symmetric topologies in blueprints.
function early_check_symmetric(d::D.EdgeField, mat::AbstractMatrix)
    T = eltype(mat)
    raw = T[]
    for (i, j, v) in edges_values(mat)
        i < j && continue
        value = check_with_ref(d, v, (i, j))
        sym = mat[j, i]
        mat[j, i] == value || conserr("The matrix should be symmetric, \
                                       but obtained different values \
                                       for [$i, $j] and [$j, $i]: \
                                       $(repr(value)) ≠ $(repr(sym)).")
        push!(raw, value)
    end
    (raw, mat)
end

# Abstract over dense/sparse matrices.
n_edges(m::AbstractMatrix) = prod(size(m))
n_edges(m::AbstractSparseMatrix) = length(findnz(m))
function edges_values(m::AbstractMatrix)
    m, n = size(m)
    ((i, j, m[i, j]) for j in 1:n, i in 1:m) # Column-major.
end
function edges_values(m::AbstractSparseMatrix)
    is, js, vs = findnz(m)
    zip(is, js, vs)
end

# The raw vector cannot be directly extracted from the adjacency list
# because input edges ordering cannot be checked.
# Collect {edges ↦ values} mapping instead.
function early_check(d::D.EdgeField, adj::Adjacency)
    T = valtype(adj)
    adj = NF.parse(Adjacency{T}, adj) # Re-parse in case the list was mutated.
    D.is_sparse(d) ? early_check_sparse(d, adj) : early_check_dense(d, adj)
end

# In the sparse case, prepare an edge to value mapping.
early_check_sparse(d::D.EdgeField, adj::Adjacency) =
    Dict((src, tgt) => check_with_ref(d, v, (src, tgt)) for (src, tgt, v) in NF.iter(adj))

# In the dense case, check that the list is actually dense
# and arange checked values in a matrix.
function early_check_dense(d::D.EdgeField, adj::Adjacency{<:Any,Int})
    T = D.type(d)
    n_src = length(NF.source_refs(adj))
    n_tgt = length(NF.target_refs(adj))
    mat = zeros(T, (n_src, n_tgt))
    if length(adj) < n_src
        for miss in 1:n_src
            miss in keys(adj) || conserr("No value provided for edges with source $miss.")
        end
    end
    for (src, targets) in adj
        if length(targets) < n_tgt
            for miss in 1:n_tgt
                miss in keys(targets) ||
                    conserr("No value provided for edge ($src, $miss).")
            end
        end
        for (tgt, v) in targets
            mat[src, tgt] = check_with_ref(d, v, (src, tgt))
        end
    end
    mat
end

# With labels as references, also collect a mapping to local/input indices.
function early_check_dense(d::D.EdgeField, adj::Adjacency{<:Any,Symbol})
    T = D.type(d)
    sources = Dict{Symbol,I}() # Filled during main iteration.
    targets = Dict(tgt => j for (j, tgt) in enumerate(NF.target_refs(adj)))
    n_src, n_tgt = length(sources), length(targets)
    mat = zeros(T, (n_src, n_tgt))
    for (i, (src, sub)) in enumerate(adj)
        sources[src] = i
        if length(sub) < length(targets)
            for miss in keys(targets)
                miss in keys(sub) || conserr("No value provided for edge ($src, $miss).")
            end
        end
        for (tgt, v) in sub
            j = targets[tgt]
            mat[i, j] = check_with_ref(d, v, (src, tgt))
        end
    end
    (mat, sources, targets)
end

#-------------------------------------------------------------------------------------------
# Late check (dispatched from the generic method in `node_field.jl`).

# Raw.
function late_check(d::D.EdgeField, model::Model, vec::Vector)
    network = NF.network(model)
    web = D.web(d)
    src, tgt = D.sidenames(D.Web(d))
    # Check number of values first.
    n = N.n_edges(network, web)
    l = length(vec)
    n == l || conserr("Wrong number of values received: expected $n, got $l.")
    # Then check values one by one, with context to produce useful reports.
    src_labels = collect(N.node_labels(network, src))
    tgt_labels = collect(N.node_labels(network, tgt))
    web = N.web(network, web)
    edges = N.edges(web.topology)
    map(enumerate(zip(edges, vec))) do (i, ((s, t), value))
        check_with_ref(d, model, value, (s, t), (src_labels[s], tgt_labels[t]), i)
    end
end

# Matrix (receive the raw vector produced during early_check).
function late_check(d::D.EdgeField, model::Model, (raw, mat)::Tuple{Vector,AbstractMatrix})
    network = NF.network(model)
    web = N.web(network, D.web(d))
    w = D.Web(d)
    src, tgt = D.sidenames(w)
    src_labels = collect(N.node_labels(network, src))
    tgt_labels = collect(N.node_labels(network, tgt))
    compare_topologies(w, web.topology, mat)
    map(edges_values(mat)) do (s, t, value)
        check_with_ref(d, model, value, (s, t), (src_labels[s], tgt_labels[t]))
    end
end

# Comparing dense matrices topology is straightforward: only size matters.
compare_topologies(d::D.Web, top::FullTopology, mat::AbstractMatrix) =
    compare_size(d, top, mat)
function compare_size(d::D.Web, top::Topology, mat::AbstractMatrix)
    web = D.web(d)
    expected = N.n_sources(top), N.n_targets(top)
    actual = size(mat)
    if expected != actual
        a, b = expected
        u, v = actual
        conserr("The expected topology size for $(repr(web)) is $a×$b \
                 but the matrix provided is $u×$v.")
    end
end

# Comparing sparse matrices requires checking every expected/provided edge.
function compare_topologies(d::D.Web, top::SparseTopology, mat::AbstractSparseMatrix)
    web = D.web(d)
    sym = D.is_symmetric(d)
    compare_size(d, top, mat)
    expected = Set(N.edges(top))
    actual = Set((i, j) for (i, j, _) in edges_values(mat) if (!sym || i <= j))
    compare_edges(d, expected, actual, (i, j) -> mat[i, j], "sparse matrix")
end

# Comparing two set of edges for identity.
function compare_edges(d::D.Web, expected::Set, actual::Set, value::Function, input)
    web = D.web(d)
    sym = D.is_symmetric(d)
    miss = setdiff(expected, actual)
    y() = sym ? " (symmetric)" : ""
    if !isempty(miss)
        src, tgt = first(miss)
        conserr(
            "Edge [$(repr(src)), $(repr(tgt))]$(y()) has no value in the provided $input.",
        )
    end
    extra = setdiff(actual, expected)
    if !isempty(extra)
        src, tgt = first(extra)
        value = value(src, tgt)
        conserr("Edge [$(repr(src)), $(repr(tgt))]$(y()) does not exist in $(repr(web)) \
                 but the $input provides a value for it: $(repr(value)).")
    end
end

# Adjacency, sparse.
function late_check(d::D.EdgeField, model::Model, edges::Dict{Tuple{R,R}}) where {R}
    network = NF.network(model)
    w = D.web(d)
    web_edges() = expected_edges(R, network, w)
    expected = Set(web_edges())
    actual = Set(keys(edges))
    val(s, t) = edges[(s, t)]
    compare_edges(D.Web(d), expected, actual, val, "adjacency list")
    # Construct raw vectors values in correct order.
    [val(s, t) for (s, t) in web_edges()]
end
function expected_edges(::Type{Int}, network::Network, web::Symbol)
    top = N.web(network, web).topology
    N.edges(top)
end
function expected_edges(::Type{Symbol}, network::Network, web::Symbol)
    web = N.web(network, web)
    src = N.class(network, web.source).index
    tgt = N.class(network, web.target).index
    ((N.to_label(src, i), N.to_label(tgt, j)) for (i, j) in N.edges(web.topology))
end

# Adjacency, dense.
late_check(d::D.EdgeField, model::Model, mat::Matrix) = throw("TODO")
function late_check(
    d::D.EdgeField,
    model::Model,
    (mat, sources, targets)::Tuple{Matrix,Dict,Dict},
)
    throw("TODO")
end

# Flat, default.
late_check(d::D.EdgeField, model::Model, value) = check(d, model, value)

#-------------------------------------------------------------------------------------------
# Implied web blueprint.

function implied_web(::D.EdgeField, Web, bp::EdgeFieldMatrixBlueprint)
    mat = data(bp)
    m, n = size(mat)
    mask = spzeros(Bool, (m, n))
    is, js, _ = findnz(mat)
    for (i, j) in zip(is, js)
        mask[i, j] = true
    end
    Web.Matrix(mask)
end

function implied_web(::D.EdgeField, Web, bp::EdgeFieldAdjacencyBlueprint)
    adj = data(bp)
    mask = NF.parse(BinAdjacency, adj)
    Web.Adjacency(mask)
end

#-------------------------------------------------------------------------------------------
# Expand.

# These provide the same `late_data` after late checking (= the raw vector).
expand!(
    d::D.EdgeField,
    model::Model,
    ::Union{EdgeFieldRawBlueprint,EdgeFieldMatrixBlueprint,EdgeFieldAdjacencyBlueprint},
    late_data::Vector,
) = expand!(d, model, late_data)

# Flat: expand the raw vector.
function expand!(d::D.EdgeField, model::Model, ::EdgeFieldFlatBlueprint, value)
    network = NF.network(model)
    top = N.web(network, D.web(d)).topology
    raw = fill(value, N.n_edges(top))
    expand!(d, model, raw)
end

function expand!(d::D.EdgeField, model::Model, data::Vector)
    network = NF.network(model)
    (webname, fieldname) = D.content(d)
    web = N.web(network, webname)
    N.add_field!(web, fieldname, data)
end

#-------------------------------------------------------------------------------------------
# Mutation: called when setting through a view.
# Input may be anything,
# but the underlying model value and the reference can be assumed to be correct.

# XXX: this is very much like the node field one except for two indices instead of one.
# Maybe it is a good opportunity to harmonize all indices handling/checking
# from the views up to here?
mutate_check(d::D.EdgeField, model::Model, value, ref) =
    try
        check_with_ref(d, WholeCheck(model), value, ref)
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "When attempting to mutate $d node field")
    end

# ==========================================================================================
# Display.

function edges_shortline(io::IO, model::Model, d::D.EdgeField)
    Field = D.CamelCaseSingular(d)
    w, f = D.content(d)
    network = NF.network(model)
    web = N.web(network, w)
    n = N.n_edges(web.topology)
    entry = web.data[f]
    s = n == 1 ? "" : "s"
    N.read(entry) do data
        min, max = extrema(data)
        vals = min == max ? "$min" : "$min to $max"
        print(io, "$Field: $vals ($n value$s).")
    end
end
