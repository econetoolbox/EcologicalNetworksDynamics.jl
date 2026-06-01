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
            import EcologicalNetworksDynamics: F, NF, D, Brought
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
            F.implied_blueprint_for(bp::Matrix, ::_Web) = NF.implied_web(d, Web, bp)
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
                $web::Brought(Web) # Not exactly useful. Keep for consistency.
                Adjacency($short, $web) = new(NF.construct(d, Adjacency, $short), $web)
                Adjacency($short; $web = _Web) = Adjacency($short, $web)
            end
            NF.data(bp::Adjacency) = bp.$short
            F.implied_blueprint_for(bp::Adjacency, ::_Web) = NF.implied_web(d, Web, bp)
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
    mod.eval(quote
        $F.shortline(io::IO, model::Model, ::$C) = $nodes_shortline(io, model, $d)
    end)

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

function check_with_ref(d::EdgeField, against::Model, value, i::EdgeIndex, l::EdgeLabel)
    try
        value = check(d, value)
        check(d, against, value, i, l)
    catch e
        e isa F.InputError || rethrow(e)
        i, j = i
        a, b = l
        with_context!(e, "On edge $(repr(a)) => $(repr(b)) ([$i, $j])")
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
