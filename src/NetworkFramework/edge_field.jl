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
    d::EdgeField;
    blueprints = [], # Extra blueprints for the component.
    requires = [], # Extra requirements for the component.
)
    # Implementation mostly adapted from web.jl and nodes.jl.
    # TODO: how much of it could be factored? There is much duplication in here.

    # TODO: have it generic over D.is_sparse(d) the day it's required.

    ew = EdgeWeb(d)
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
        F.early_check(bp::Raw) = NF.early_check(d, bp)
        F.late_check(model, bp::Raw, data) = NF.late_check(d, model, bp, data)
        F.expand!(model, bp::Raw, data) = NF.expand!(d, model, bp, data)
        NF.define_blueprint(Raw, "raw values")
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
            F.implied_blueprint_for(bp::Matrix, ::Type{_Web}) = NF.implied_web(d, Web, bp)
            F.early_check(bp::Matrix) = NF.early_check(d, bp)
            F.late_check(model, bp::Matrix, data) = NF.late_check(d, model, bp, data)
            F.expand!(model, bp::Matrix, data) = NF.expand!(d, model, bp, data)
            NF.define_blueprint(Matrix, $"a $(sparse ? "sparse " : "")matrix")
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
            F.implied_blueprint_for(bp::Adjacency, ::Type{_Web}) =
                NF.implied_web(d, Web, bp)
            F.early_check(bp::Adjacency) = NF.early_check(d, bp)
            F.late_check(model, bp::Adjacency, data) = NF.late_check(d, model, bp, data)
            F.expand!(model, bp::Adjacency, data) = NF.expand!(d, model, bp, data)
            NF.define_blueprint(Adjacency, $"[$src => [$tgt => $field]] adjacency list")
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
                end
                NF.data(bp::Flat) = bp.$short
                F.early_check(bp::Flat) = NF.early_check(d, bp)
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
    mod.eval(
        quote
            $F.shortline(io::IO, model::Model, ::$C) = $NF.edges_shortline(io, model, $d)
        end,
    )

    comp

end

# ==========================================================================================
# Extracted logic + extension points.
# Mostly duplicated from node field.

#-------------------------------------------------------------------------------------------
# Contextless check.

check(d::EdgeField, value) = inputconvert(D.type(d), value)

const EdgeIndex = Tuple{Int,Int}
const EdgeLabel = Tuple{Symbol,Symbol}

check_with_ref(d::EdgeField, value, (i, j)::EdgeIndex) =
    try
        check(d, value)
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "On edge [$i, $j]")
    end
check_with_ref(d::EdgeField, value, (a, b)::EdgeLabel) =
    try
        check(d, value)
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "On edge $(repr(a)) => $(repr(b))")
    end
# Useful when constructing from raw values because edge indices are unknown yet.
check_with_raw_ref(d::EdgeField, value, i::Int) =
    try
        check(d, value)
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "At raw edge value [$i]")
    end

#-------------------------------------------------------------------------------------------
# Model-aware checks.

function check_with_ref(
    d::EdgeField,
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
function indexes(d::EdgeField, network::Network)
    web = D.web(d)
    N.index.(network, D.sidenames(web))
end

# Infer any reference type from the other one.
function check_with_ref(d::EdgeField, against, value, (i, j)::EdgeIndex)
    model = get_model(against)
    network = NF.network(model)
    src, tgt = indexes(d, network)
    (a, b) = N.to_label.((src, tgt), (i, j))
    check_with_ref(d, model, value, (i, j), (a, b))
end
function check_with_ref(d::EdgeField, against, value, (a, b)::EdgeLabel)
    model = get_model(against)
    network = NF.network(model)
    src, tgt = indexes(d, network)
    (i, j) = N.to_index.((src, tgt), (a, b))
    check_with_ref(d, model, value, (i, j), (a, b))
end

#-------------------------------------------------------------------------------------------
# Construct.

# From raw edges.
function construct(d::EdgeField, ::Type{<:EdgeFieldRawBlueprint}, raw)
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
function construct(d::EdgeField, ::Type{<:EdgeFieldMatrixBlueprint}, raw)
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

function checkmat(d::EdgeField, mat::Matrix)
    m, n = size(mat)
    for i in 1:m, j in 1:n
        value = mat[i, j]
        check_with_ref(d, value, (i, j))
    end
end

function checkmat(d::EdgeField, mat::SparseMatrix)
    is, js, vals = findnz(mat)
    for (i, j, value) in zip(is, js, vals)
        check_with_ref(d, value, (i, j))
    end
end

# From adjacency lists.
function construct(d::EdgeField, ::Type{<:EdgeFieldAdjacencyBlueprint}, raw)
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

function construct(d::EdgeField, Field::Component, input; _...)
    parsed = parse(d, input)
    construct_from_parsed(d, Field, parsed)
end

construct_from_parsed(::EdgeField, Field::Component, raw::Vector) = Field.Raw(raw)
construct_from_parsed(::EdgeField, Field::Component, raw::AbstractMatrix) =
    Field.Matrix(raw)
construct_from_parsed(::EdgeField, Field::Component, raw::Adjacency) = Field.Adjacency(raw)

function parse(d::EdgeField, input)
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
function early_check(d::EdgeField, vec::Vector)
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
function early_check(d::EdgeField, mat::AbstractMatrix)
    D.is_symmetric(D.EdgeWeb(d)) && return early_check_symmetric(d, mat)
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
function early_check_symmetric(d::EdgeField, mat::AbstractMatrix)
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
    ((i, j, m[i, j]) for i in 1:m, j in 1:n)
end
function edges_values(m::AbstractSparseMatrix)
    is, js, vs = findnz(m)
    zip(is, js, vs)
end

# The raw vector cannot be directly extracted from the adjacency list
# because there is no guarantee on the input edges ordering.
# Take this first iteration opportunity to count provided values.
function early_check(d::EdgeField, adj::Adjacency)
    n = 0
    for (src, targets) in adj
        for (tgt, v) in targets
            check_with_ref(d, v, (src, tgt))
            n += 1
        end
    end
    (n, adj)
end

#-------------------------------------------------------------------------------------------
# Late check (dispatched from the generic method in `node_field.jl`).

# Raw.
function late_check(d::EdgeField, model::Model, vec::Vector)
    network = NF.network(model)
    web = D.web(d)
    src, tgt = D.sidenames(D.EdgeWeb(d))
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
function late_check(d::EdgeField, model::Model, (raw, mat)::Tuple{Vector,AbstractMatrix})
    network = NF.network(model)
    web = N.web(network, D.web(d))
    w = D.EdgeWeb(d)
    src, tgt = D.sidenames(w)
    src_labels = collect(N.node_labels(network, src))
    tgt_labels = collect(N.node_labels(network, tgt))
    compare_topologies(w, web.topology, mat, web.name)
    map(edges_values(mat)) do (s, t, value)
        check_with_ref(d, model, value, (s, t), (src_labels[s], tgt_labels[t]))
    end
end

compare_topologies(::EdgeWeb, top::FullTopology, mat::AbstractMatrix, web::Symbol) =
    compare_size(top, mat, web)
function compare_size(top::Topology, mat::AbstractMatrix, web::Symbol)
    expected = N.n_sources(top), N.n_targets(top)
    actual = size(mat)
    if expected != actual
        a, b = expected
        u, v = actual
        conserr("The expected topology size for $(repr(web)) is $a×$b \
                 but the matrix provided is $u×$v.")
    end
end

function compare_topologies(
    d::EdgeWeb,
    top::SparseTopology,
    mat::AbstractSparseMatrix,
    web::Symbol,
)
    compare_size(top, mat, web)
    sym = D.is_symmetric(d)
    expected = Set(N.edges(top))
    actual = Set((i, j) for (i, j, _) in edges_values(mat) if (!sym || i <= j))
    miss = setdiff(expected, actual)
    y() = sym ? " (symmetric)" : ""
    if !isempty(miss)
        i, j = first(miss)
        conserr("Edge [$i, $j]$(y()) has no value in the provided sparse matrix.")
    end
    extra = setdiff(actual, expected)
    if !isempty(extra)
        i, j = first(extra)
        value = mat[i, j]
        conserr("Edge [$i, $j]$(y()) does not exist in $(repr(web)) \
                 but the matrix provides a value for it: $(repr(value)).")
    end
end

# Adjacency.
function late_check(d::EdgeField, model::Model, (n, adj)::Union{Int,Adjacency})
    network = NF.network(model)
    w = D.EdgeWeb(d)
    web = D.web(d)
    src, tgt = D.sidenames(w)
    # Check number of values.
    e = N.n_edges(network, web)
    e == n || conserr("Wrong number of values received: ")
end

#-------------------------------------------------------------------------------------------
# Expand.

expand!(
    d::EdgeField,
    model::Model,
    # These provide the same `late_data` after late checking (= a raw vector).
    ::Union{EdgeFieldRawBlueprint,EdgeFieldMatrixBlueprint,EdgeFieldAdjacencyBlueprint},
    late_data::Vector,
) = expand!(d, model, late_data)

function expand!(d::EdgeField, model::Model, data::Vector)
    network = NF.network(model)
    (webname, fieldname) = D.content(d)
    web = N.web(network, webname)
    N.add_field!(web, fieldname, data)
end

#-------------------------------------------------------------------------------------------
# Display.

function edges_shortline(io::IO, model::Model, d::EdgeField)
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
