"Expand to a web field."
abstract type EdgeFieldBlueprint <: Blueprint end

"Expand to a web field from a vector of raw values."
abstract type EdgeFieldRawBlueprint <: EdgeFieldBlueprint end

"Expand to a web field from a matrix."
abstract type EdgeFieldMatrixBlueprint <: EdgeFieldBlueprint end

"Expand to a web field from an adjacency list."
abstract type EdgeFieldAdjacencyBlueprint <: EdgeFieldBlueprint end

"Expand to a web field from a single value."
abstract type EdgeFieldFlatBlueprint <: EdgeFieldBlueprint end

"Typical setup for a component bringing a new web field to the network."
function define_web_field_component(
    mod::Module,
    s::SL.EdgeField;
    blueprints = [], # Extra blueprints for the component.
    requires = [], # Extra requirements for the component.
)
    w = SL.web(s)
    Web = SL.component(w)
    web, field = SL.content(s)
    src, tgt = SL.sourcename(w), SL.targetname(w)
    value, values, Value, Values, short = SL.name_variants(s)
    T = SL.type(s)
    Value_ = Symbol(Value, :_) # Blueprints module name.
    _Value = Symbol(:_, Value) # Component type name.

    # First attempt to polymorphism over sparsity.
    sparse = SL.is_sparse(s)
    Mat = sparse ? SparseMatrix : Matrix

    # ======================================================================================
    # Blueprints for the component.

    bpmod = mod.eval(
        (
            quote
                module $Value_
                import EcologicalNetworksDynamics.Interface: IT, SL, @bp_construct
                const w, s, T, sparse, Mat, Web = $w, $s, $T, $sparse, $Mat, $Web
                const _Web = typeof(Web)
                end
            end
        ).args |> last,
    )

    #---------------------------------------------------------------------------------------
    # From raw values.

    bpmod.eval(quote
        mutable struct Raw <: IT.EdgeFieldRawBlueprint
            $short::Vector{T}
            @bp_construct Raw
        end
        export Raw
        IT.register_blueprint(Raw, "raw values"; s)
    end)

    #---------------------------------------------------------------------------------------
    # From a matrix.

    bpmod.eval(
        quote
            mutable struct Matrix <: IT.EdgeFieldMatrixBlueprint
                $short::Mat{T}
                @bp_construct Matrix
            end
            export Matrix
            IT.register_blueprint(Matrix, "a $(sparse ? "sparse " : "")matrix"; s,
                implied = [Web], # Imply web from matrix structure.
            )
        end,
    )

    #---------------------------------------------------------------------------------------
    # From an adjacency list.

    bpmod.eval(
        quote
            mutable struct Adjacency <: IT.EdgeFieldAdjacencyBlueprint
                $short::IT.Adjacency{T}
                @bp_construct Adjacency
            end
            export Adjacency
            IT.register_blueprint(Adjacency,
                $"[$src => [$tgt => $field]] adjacency list"; s,
                implied = [Web], # Imply web from adjacency list keys.
            )
        end,
    )

    #---------------------------------------------------------------------------------------
    # From a scalar broadcasted to all nodes in the web (if meaningful).

    if may_flat(s)
        bpmod.eval(
            quote
                mutable struct Flat <: IT.EdgeFieldFlatBlueprint
                    $short::T
                    @bp_construct Flat
                end
                export Flat
                IT.register_blueprint(Flat, "uniform value"; s)
            end,
        )
    end

    # ======================================================================================
    # The component itself and generic blueprints constructors.

    S = typeof(s)
    cp = mod.eval(
        quote
            IT.define_component(
                $(Meta.quot(Value)),
                $mod;
                requires = ($Web, $(requires...)),
                blueprints = [$bpmod, $(blueprints...)],
            )
        end,
    )
    CP = typeof(cp)
    mod.eval(
        quote
            $SL.component(::$S) = $cp
            (::$_Value)($short, args...; kwargs...) =
                $construct($s, $Value, $short, args...; kwargs...)
        end,
    )

    if may_flat(s)
        R = flat(s) # Receiver type.
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
                using EcologicalNetworksDynamics.Interface: VW, IT, SL, Network, Model
                const s, prop, CP = $s, $prop, $CP
                SL.viewtype(::typeof(s)) = VW.EdgeFieldView
                get_value(::Network, md::Model) = VW.field_view(s, md)
                IT.define_method(get_value; read_as = prop, depends = [CP])
                if !SL.readonly(s)
                    set_value!(::Network, md::Model, input) =
                        IT.mut_set!(md, s, IT.wholedata, input)
                    IT.define_method(set_value!; write_as = prop, depends = [CP])
                end
                end
            end
        ).args |> last,
    )

    # Display.
    IT.eval(
        quote
            CS.shortline(io::IO, md::Model, ::$CP) = edges_shortline(io, md, $s)
        end,
    )

    (cp, CP)

end

# ==========================================================================================
# Specialization.
# Mostly inspired from NodeField (read there for precision).

#-------------------------------------------------------------------------------------------
# Construct.

function construct(s::SL.EdgeField, Field::Component, input, args...; kwargs...)
    T = SL.type(s)
    Mat = SL.is_sparse(s) ? SparseMatrix : Matrix
    tries = (
        Vector{T} => x -> Field.Raw(x, args...; kwargs...),
        Mat{T} => x -> Field.Matrix(x, args...; kwargs...),
        Adjacency{T} => x -> Field.Adjacency(x, args...; kwargs...),
    )
    if may_flat(s)
        tries = (
            T => x -> Field.Flat(x, args...; kwargs...), # (try flat first)
            tries...,
        )
    end
    try
        try_convert(input, tries...)
    catch e
        e isa BlueprintError && rethrow(e) # Thrown by underlying constructor: already ok.
        e isa LibError || rethrow(e) # Otherwise upgrade.
        e = CheckError(e)
        e.s = s
        rethrow(e)
    end
end

#-------------------------------------------------------------------------------------------
# Implied web.

function implied(s::SL.EdgeField, Web::Component, bp::EdgeFieldMatrixBlueprint)
    if SL.is_dense(s)
        # TODO: trivial dense web constructor assuming source and target exist,
        # not yet implemented?
        Web.Trivial()
    else
        mat = data(bp)
        m, n = size(mat)
        mask = spzeros(Bool, (m, n))
        for (i, j, _) in zip(findnz(mat)...)
            mask[i, j] = true
        end
        Web.Matrix(mask)
    end
end

function implied(::SL.EdgeField, Web::Component, bp::EdgeFieldAdjacencyBlueprint)
    adj = data(bp)
    mask = convert(BinAdjacency, adj)
    Web.Adjacency(mask)
end

#-------------------------------------------------------------------------------------------
# Early_check.

const EdgeRef = Tuple{Ref,Ref}

early_check(s::SL.EdgeField, x, ::Union{Tuple{Ref},EdgeRef}) = early_check(s, x)

# On construction, check all but alias, discarding possible conversion/lowering.
function cst_early_check(
    BP::Type{<:EdgeFieldBlueprint},
    data::Union{Vector,AbstractMatrix,Adjacency},
)
    s = selector(BP)
    SL.is_symmetric(SL.web(s)) && check_symmetric(s, data)
    for (r, x) in edge_pairs(data)
        ref = Tuple(r)
        urefguard(ref) do
            SL.is_dense(s) && check_dense_ref(BP, ref, data)
            early_check(s, x, ref)
        end
    end
    data
end
edge_pairs(data) = pairs(data)
edge_pairs(adj::Adjacency) = I.map(((src, tgt, x),) -> ((src, tgt), x), iter(adj))

# On expansion, checked values (possibly lowered) are collected into a linearized vec.
function bp_early_check(
    bp::Union{EdgeFieldRawBlueprint,EdgeFieldMatrixBlueprint,EdgeFieldAdjacencyBlueprint},
)
    s, data = selector(bp), IT.data(bp)
    SL.is_symmetric(SL.web(s)) && check_symmetric(s, data)
    early_lower(s, data) do ref, x
        urefguard(ref) do
            SL.is_dense(s) && check_dense_ref(typeof(bp), ref, data)
            early_check(s, x, ref)
        end
    end
end

# On mutation, don't check for density.
function mut_early_check(s::SL.EdgeField, data::Union{Vector,AbstractMatrix,Adjacency})
    SL.is_symmetric(SL.web(s)) && check_symmetric(s, data)
    early_lower(s, data) do ref, x
        urefguard(ref) do
            early_check(s, x, ref)
        end
    end
end

function check_symmetric(s::SL.EdgeField, mat::AbstractMatrix)
    m, n = size(data)
    m == n || throw("meaningless check: this is a bug in the package")
    for i in 1:n, j in 1:(i-1)
        mat[i, j] == mat[j, i] && continue
        checkerr(mat[i, j],
            "The matrix should be symmetric, \
             a different value was obtained for [$j, $i]: " * rept(mat[j, i]);
            s, uref = (i, j))
    end
end

#-------------------------------------------------------------------------------------------
# Symmetry check.

# For adjacency list, accept that the symmetric value be missing, but not different.
function check_symmetric(s::SL.EdgeField, adj::Adjacency)
    for (src, sub) in pairs(adj)
        for (tgt, x) in pairs(sub)
            haskey(adj, tgt) || continue
            s = adj[tgt]
            haskey(s, src) || continue
            y = s[src]
            x == y && continue
            checkerr(x,
                "The adjacency list should be symmetric, \
                 a different value was obtained for [$(repr(tgt)), $(repr(src))]: " *
                rept(y); s, uref = (src, tgt))
        end
    end
end

check_symmetric(::SL.EdgeField, v::Vector) = v # (nothing to check then)

#-------------------------------------------------------------------------------------------
# Density check.

# Index-maps need to be dense if the underlying web is: cannot be holed.
function check_dense_ref(
    ::Type{<:EdgeFieldBlueprint},
    (src, tgt)::EdgeRef,
    adj::Adjacency{<:Any,Int},
)
    # (counting target refs implies one whole iteration, hopefully loop-extracted)
    n_src, n_tgt = length(adj), length(target_refs(adj))
    src <= n_src && tgt <= n_tgt && return (src, tgt)
    checkerr((src, tgt),
        "The web is dense and of size $((n_src, n_tgt)) so no index can be $((src, tgt)).")
end
check_dense_ref(::Type{<:EdgeFieldBlueprint}, ref, _) = ref # (nothing to check then)

#-------------------------------------------------------------------------------------------
# Early lowering.
# TODO: skip reallocation if the early_check extension point does not convert values?

early_lower(fn::Function, ::SL.EdgeField, data::Union{Vector,Matrix}) =
    [fn(Tuple(i), x) for (i, x) in pairs(data)]

function early_lower(fn::Function, ::SL.EdgeField, spm::SparseMatrix)
    res = similar(spm)
    for (i, j, x) in zip(findnz(spm)...)
        res[i, j] = fn((i, j), x)
    end
    res
end

function early_lower(fn::Function, ::SL.EdgeField, adj::Adjacency)
    res = typeof(adj)()
    for (src, sub) in adj
        early_check_ref(adj, src)
        s = typeof(sub)()
        for (tgt, x) in sub
            early_check_ref(adj, src, tgt)
            s[tgt] = fn((src, tgt), x)
        end
        res[src] = s
    end
    res
end
# Indices can be early-checked for at least being positive.
early_check_ref(::Adjacency, label...) = label
early_check_ref(::Adjacency{<:Any,Int}, i::Int) = early_check_index(i, (i,))
early_check_ref(::Adjacency{<:Any,Int}, i::Int, j::Int) = early_check_index(j, (i, j))
early_check_index(i, uref) =
    1 <= i || checkerr(i, "Integer reference must be a positive index."; uref)

#-------------------------------------------------------------------------------------------
# Late check.
# Take this opportunity to lower into a linearized vector.

const EdgeMRef = Tuple{MRef,MRef}

# Extension point.
late_check(::Model, ::SL.EdgeField, x, ::EdgeMRef) = x

# Guard the above to upgrade exceptions.
_late_check(md::Model, s::SL.EdgeField, x, mref::EdgeMRef) =
    try
        late_check(md, s, x, mref)
    catch e
        e isa LibError || rethrow(e)
        if !(e isa CheckError)
            e = CheckError(e)
        end
        e.ref = ModelRef(mref)
        rethrow(e)
    end

# When obtaining a raw vector.
function late_check(md::Model, s::SL.EdgeField, vec::Vector)
    # Check plain number of provided values.
    wb = ST.web(md, s)
    exp, act = ST.n_edges(wb), length(vec)
    if exp != act
        gr, cy = col.((green, cyan))
        _, s, are = nsa(exp)
        checkerr(
            vec,
            "There $are $(gr(exp)) edge$s to valuate, \
             but the vector is of size $(gr(act)).",
        )
    end
    # Then check values one by one.
    tp = wb.topology
    map(zip(ST.edges(tp), vec)) do ((i, j), x)
        a, b = ST.to_label(md, s, i, j)
        _late_check(md, s, x, ((i, a), (j, b)))
    end
end

# When obtaining a matrix.
function late_check(md::Model, s::SL.EdgeField, mat::AbstractMatrix)
    # Check dimensions.
    (src, tgt) = ST.sides(md, s)
    exp, act = length.((src, tgt)), size(mat)
    if exp != act
        (ns, ss), (nt, st) = IT.ns.(exp)
        gr, cy = col.((green, cyan))
        checkerr(mat,
            "There are $(gr(ns)) source$ss and $(gr(nt)) target$st, \
             but the matrix received is of size $(cy(act)).")
    end
    # Then check values one by one as we lower into a linear vector.
    late_lower(md, s, mat)
end

# When obtaining an adjacency list.
late_check(md::Model, s::SL.EdgeField, adj::Adjacency) = late_lower(md, s, adj)
mut_late_check(md::Model, s::SL.EdgeField, adj::Adjacency) =
    late_lower(md, s, adj, Val(false))

# No topology check required for dense matrices.
function late_lower(md::Model, s::SL.EdgeField, mat::Matrix)
    [
        begin
            (i, j) = Tuple(ij)
            a, b = ST.to_label(md, s, i, j)
            _late_check(md, s, x, ((i, a), (i, b)))
        end
        for (ij, x) in pairs(mat) # Column-major as expected.
    ]
end

# Check edges consistency,
# but also take this opportunity to lower sparse matrices into a raw vector.
function late_lower(
    md::Model,
    sl::SL.EdgeField,
    data::Union{SparseMatrix,Adjacency},
    ::Val{complete} = Val(true),
) where complete
    T = SL.type(sl)
    # Expected set of edges.
    tp = ST.web(md, sl).topology
    exp = tp |> ST.edges |> Set
    # Actual set of edges.
    act = Dict{Tuple{Int,Int},valtype(data)}()
    # Collect into a lower vector.
    lower = data isa SparseMatrix
    low = lower ? sizehint!(T[], ST.n_edges(tp)) : nothing
    for (i, j, x) in actual_edges(md, sl, data)
        act[(i, j)] = x
        lower || continue
        push!(low, x)
    end
    function render(set)
        pairs = I.map(set) do (i, j)
            a, b = ST.to_label(md, sl, i, j)
            (i, a) => (j, b)
        end |> collect |> sort!
        join_elided(pairs, ", ", " and "; coleach = green)
    end
    miss = setdiff(exp, keys(act))
    if complete && !isempty(miss)
        s, them, exist, etc =
            length(miss) == 1 ?
            ("", "it", "exists", "") :
            ("s", "them", "exist", " etc.")
        w, f = SL.webname(sl), SL.fieldname(sl)
        i, j = first(miss)
        null = explicit_null(md, sl, data, f, i, j)
        checkerr(data,
            "Missing: the $green$w$reset edge$s $(render(miss)) $exist, \
             but no value is provided for $them.\n\
             To explicitly make $them null, \
             try something along $black`$null`$reset$etc (or equivalent).")
    end
    unexp = setdiff(keys(act), exp)
    if !isempty(unexp)
        w = SL.webname(sl)
        are, s =
            length(unexp) == 1 ?
            ("is", "", SL.snake_case_singular) :
            ("are", "s", SL.snake_case_plural)
        nosuch = render(unexp)
        unexp = I.map(unexp) do (i, j)
            pair = if data isa Adjacency{<:Any,Symbol}
                ST.to_label(md, sl, i, j)
            else
                (i, j)
            end
            pair => act[(i, j)]
        end |> collect |> sort!
        checkerr(unexp,
            "Received unexpected value$s: \
             there $are no such $green$w$reset edge$s: $nosuch.")
    end
    lower ? low : data
end
valtype(spm::SparseMatrix) = eltype(spm)
explicit_null(::Model, ::SL.EdgeField, ::SparseMatrix, f, i, j) = "$f[$i, $j] = 0"
function explicit_null(::Model, ::SL.EdgeField, ::Adjacency{<:Any,Int}, f, src, tgt)
    "$f[$(repr(src))][$(repr(tgt))] = 0"
end
function explicit_null(md::Model, s::SL.EdgeField, ::Adjacency{<:Any,Symbol}, f, src, tgt)
    a, b = ST.to_label(md, s, src, tgt)
    "$f[$(repr(a))][$(repr(b))] = 0"
end

actual_edges(::Model, ::SL.EdgeField, spm::SparseMatrix) = zip(findnz(spm)...)
function actual_edges(md::Model, s::SL.EdgeField, adj::Adjacency{<:Any,Int})
    src, tgt = ST.sides(md, s)
    I.map(iter(adj)) do (i, j, x)
        map(zip((i, j), (src, tgt))) do (index, cl)
            n = length(cl)
            1 <= index <= n && return
            c = "$green$(cl.name)$reset"
            checkerr((i, j),
                "Not an index among $green$n$reset $c nodes: $cyan$index$reset.";
                uref = (i, j))
        end
        (i, j, x)
    end
end

function actual_edges(md::Model, s::SL.EdgeField, adj::Adjacency{<:Any,Symbol})
    src, tgt = ST.sides(md, s)
    I.map(iter(adj)) do (a, b, x)
        (i, j) = map(zip((a, b), (src, tgt))) do (l, cl)
            ix = cl.index
            l in ix && return ST.to_index(ix, l)
            c = "$green$(cl.name)$reset"
            checkerr((a, b), "Not a $c node label: $cyan$(repr(l))$reset."; uref = (a, b))
        end
        (i, j, x)
    end
end

# ==========================================================================================
# Expand.

# Data should have already been lowered to the correct vector at this point.
function expand!(md::Model, s::SL.EdgeField, vec::Vector)
    wb, f = ST.web(md, s), SL.fieldname(s)
    ST.add_field!(wb, f, vec)
end

# Lowering adjacency lists, assuming everything checked.
function expand!(md::Model, s::SL.EdgeField, adj::Adjacency)
    # Reorder values into canonical edge order.
    R = reftype(adj)
    tp = ST.web(md, s).topology
    vec = [
        begin
            i, j = ST.to_ref(R, md, s, i, j)
            adj[i][j]
        end
        for (i, j) in ST.edges(tp)
    ]
    expand!(md, s, vec)
end

# Lowering flat values.
function expand!(md::Model, s::SL.EdgeField, flat)
    n = ST.n_edges(ST.web(md, s))
    vec = fill(flat, n)
    expand!(md, s, vec)
end

# If not, then just trust whoever only lowered to a matrix yet.
function expand!(md::Model, s::SL.EdgeField, mat::AbstractMatrix)
    vec = if SL.is_dense(s)
        mat[:]
    elseif mat isa SparseMatrix
        nonzeros(mat)
    else
        tp = ST.web(md, s).topology
        [mat[i, j] for (i, j) in ST.edges(tp)]
    end
    expand!(md, s, vec)
end

#-------------------------------------------------------------------------------------------
# Obtain.

function obtain(vw::VW.EdgeFieldView, (a, b)::Tuple{Ref,Ref})
    tp = ST.topology(vw)
    i, j = ST.to_index(vw, a, b)
    if SL.is_sparse(vw) && !ST.is_edge(tp, i, j)
        T = eltype(vw)
        zero(T)
    else
        i_raw = ST.edge(tp, i, j)
        read(ST.entry(vw)) do data
            data[i_raw]
        end
    end
end

# ==========================================================================================
#  Mutate.

#-------------------------------------------------------------------------------------------
# Convert RHS.

function convert(s::SL.EdgeField, input)
    T = SL.type(s)
    Mat = SL.is_dense(s) ? Matrix : SparseMatrix
    try_convert(input, T, Vector{T}, Mat{T}, Adjacency{T})
end

#-------------------------------------------------------------------------------------------
# Target whole data the "reassign-like".

# Complete.
function mutate!(md::Model, s::SL.EdgeField, ::WholeData, raw) # (vec or flat)
    ST.mutate!(ST.entry(md, s)) do edges
        edges .= raw
    end
end

# Maybe incomplete.
function mutate!(md::Model, s::SL.EdgeField, ::WholeData, adj::Adjacency)
    tp = ST.web(md, s).topology
    src, tgt = map(s -> s.index, ST.sides(md, s))
    ST.mutate!(ST.entry(md, s)) do edges
        for (s, t, x) in iter(adj)
            i = ST.edge(tp, ST.to_index.((src, tgt), (s, t)))
            edges[i] = x
        end
    end
end

# Single-edge.
function mutate!(md::Model, s::SL.EdgeField, (i, j)::Tuple{Int,Int}, x)
    tp = ST.web(md, s).topology
    i_edge = ST.edge(tp, i, j)
    ST.mutate!(ST.entry(md, s)) do edges
        edges[i_edge] = x
    end
end

# ==========================================================================================
# Display.

function edges_shortline(io::IO, md::Model, sl::SL.EdgeField)
    cc, fc, rs = CS.component_color, CS.field_color, reset
    fr(x) = "$fc$x$rs"
    Field = SL.CamelCaseSingular(sl)
    n, s = ST.web(md, sl).topology |> ST.n_edges |> ns
    ST.read(ST.entry(md, sl)) do data
        min, max = extrema(data)
        vals = min == max ? fr(min) : "$(fr(min)) to $(fr(max))"
        print(io, "$cc$Field$rs: $vals ($(fr(n)) value$s).")
    end
end
