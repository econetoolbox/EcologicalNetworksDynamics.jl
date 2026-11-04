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
    d::D.EdgeField;
    blueprints = [], # Extra blueprints for the component.
    requires = [], # Extra requirements for the component.
)
    w = D.Web(d)
    Web = D.CamelCase(w)
    web, field = D.content(d)
    src, tgt = D.sourcename(w), D.targetname(w)
    value, values, Value, Values, short = D.name_variants(d)
    T = D.type(d)
    Value_ = Symbol(Value, :_) # Blueprints module name.
    _Value = Symbol(:_, Value) # Component type name.

    # First attempt to polymorphism over sparsity.
    sparse = D.is_sparse(d)
    Mat = sparse ? SparseMatrix : Matrix

    # ======================================================================================
    # Blueprints for the component.

    bpmod = mod.eval(
        (
            quote
                module $Value_
                import EcologicalNetworksDynamics.NetworkFramework: F, NF, D, @bp_construct
                const w, d, T, sparse, Mat = $w, $d, $T, $sparse, $Mat
                const Web = D.component(w)
                const _Web = typeof(Web)
                end
            end
        ).args |> last,
    )

    #---------------------------------------------------------------------------------------
    # From raw values.

    bpmod.eval(quote
        mutable struct Raw <: NF.EdgeFieldRawBlueprint
            $short::Vector{T}
            @bp_construct Raw
        end
        export Raw
        NF.register_blueprint(Raw, "raw values"; d, depends = [Web])
    end)

    #---------------------------------------------------------------------------------------
    # From a matrix.

    bpmod.eval(
        quote
            mutable struct Matrix <: NF.EdgeFieldMatrixBlueprint
                $short::Mat{T}
                @bp_construct Matrix
            end
            export Matrix
            NF.register_blueprint(Matrix, "a $(sparse ? "sparse " : "")matrix"; d,
                depends = [Web])
        end,
    )

    #---------------------------------------------------------------------------------------
    # From an adjacency list.

    bpmod.eval(
        quote
            mutable struct Adjacency <: NF.EdgeFieldAdjacencyBlueprint
                $short::NF.Adjacency{T}
                @bp_construct Adjacency
            end
            export Adjacency
            NF.register_blueprint(Adjacency,
                $"[$src => [$tgt => $field]] adjacency list"; d, depends = [Web])
        end,
    )

    #---------------------------------------------------------------------------------------
    # From a scalar broadcasted to all nodes in the web (if meaningful).

    if may_flat(d)
        bpmod.eval(
            quote
                mutable struct Flat <: NF.EdgeFieldFlatBlueprint
                    $short::T
                    @bp_construct Flat
                end
                export Flat
                NF.register_blueprint(Flat, "uniform value"; d, depends = [Web])
            end,
        )
    end

    # ======================================================================================
    # The component itself and generic blueprints constructors.

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
                using EcologicalNetworksDynamics.NetworkFramework: V, NF, D, Network, Model
                const d, prop, CP = $d, $prop, $CP
                D.viewtype(::typeof(d)) = V.EdgeFieldView
                get_value(::Network, m::Model) = V.field_view(d, m)
                NF.define_method(get_value; read_as = prop, depends = [CP])
                if !D.readonly(d)
                    set_value!(::Network, m::Model, input) = assign!(d, m, input)
                    NF.define_method(set_value!; write_as = prop, depends = [CP])
                end
                end
            end
        ).args |> last,
    )

    # Display.
    NF.eval(
        quote
            F.shortline(io::IO, md::Model, ::$CP) = edges_shortline(io, md, $d)
        end,
    )

    (cp, CP)

end

# ==========================================================================================
# Specialization.
# Mostly inspired from NodeField (read there for precision).

#-------------------------------------------------------------------------------------------
# Construct.

function construct(d::D.EdgeField, Field::Component, input, args...; kwargs...)
    T = D.type(d)
    Mat = D.is_sparse(d) ? SparseMatrix : Matrix
    tries = (
        Vector{T} => x -> Field.Raw(x, args...; kwargs...),
        Mat{T} => x -> Field.Matrix(x, args...; kwargs...),
        Adjacency{T} => x -> Field.Adjacency(x, args...; kwargs...),
    )
    if may_flat(d)
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
        e.d = d
        rethrow(e)
    end
end

#-------------------------------------------------------------------------------------------
# Implied web.

function implied(d::D.EdgeField, Web::Component, bp::EdgeFieldMatrixBlueprint)
    if D.is_dense(d)
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

function implied(::D.EdgeField, Web::Component, bp::EdgeFieldAdjacencyBlueprint)
    adj = data(bp)
    mask = convert(BinAdjacency, adj)
    Web.Adjacency(mask)
end

#-------------------------------------------------------------------------------------------
# Early_check.

const EdgeRef = Tuple{Ref,Ref}

early_check(d::D.EdgeField, x, ::Union{Tuple{Ref},EdgeRef}) = early_check(d, x)

# On construction, check all but alias, discarding possible conversion/lowering.
function cst_early_check(
    BP::Type{<:EdgeFieldBlueprint},
    data::Union{Vector,AbstractMatrix,Adjacency},
)
    d = dispatcher(BP)
    D.is_symmetric(first(D.Web(d))) && check_symmetric(d, data)
    for (ref, x) in edge_pairs(data)
        urefguard(Tuple(ref)) do
            D.is_dense(d) && check_dense_ref(BP, ref, data)
            early_check(d, x, ref)
        end
    end
    data
end
edge_pairs(data) = pairs(data)
edge_pairs(adj::Adjacency) = I.map(((src, tgt, x)) -> ((src, tgt), x), iter(adj))

# On expansion, checked values (possibly lowered) are collected into a linearized vec.
function bp_early_check(
    bp::Union{EdgeFieldRawBlueprint,EdgeFieldMatrixBlueprint,EdgeFieldAdjacencyBlueprint},
)
    d, data = dispatcher(bp), NF.data(bp)
    D.is_symmetric(first(D.Web(d))) && check_symmetric(d, data)
    early_lower(d, data) do ref, x
        urefguard(ref) do
            D.is_dense(d) && check_dense_ref(typeof(bp), ref, data)
            early_check(d, x, ref)
        end
    end
end

# On mutation, don't check for density.
function mut_early_check(d::D.EdgeField, data::Union{Vector,AbstractMatrix,Adjacency})
    D.is_symmetric(first(D.Web(d))) && check_symmetric(d, data)
    early_lower(d, data) do ref, x
        urefguard(ref) do
            early_check(d, x, ref)
        end
    end
end

function check_symmetric(d::D.EdgeField, mat::AbstractMatrix)
    m, n = size(data)
    m == n || throw("meaningless check: this is a bug in the package")
    for i in 1:n, j in 1:(i-1)
        mat[i, j] == mat[j, i] && continue
        checkerr(mat[i, j],
            "The matrix should be symmetric, \
             a different value was obtained for [$j, $i]: " * rept(mat[j, i]);
            d, uref = (i, j))
    end
end

#-------------------------------------------------------------------------------------------
# Symmetry check.

# For adjacency list, accept that the symmetric value be missing, but not different.
function check_symmetric(d::D.EdgeField, adj::Adjacency)
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
                rept(y); d, uref = (src, tgt))
        end
    end
end

check_symmetric(::D.EdgeField, v::Vector) = v # (nothing to check then)

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

early_lower(fn::Function, ::D.EdgeField, data::Union{Vector,Matrix}) =
    [fn((i,), x) for (i, x) in pairs(data)]

function early_lower(fn::Function, ::D.EdgeField, spm::SparseMatrix)
    res = similar(spm)
    for (i, j, x) in zip(findnz(spm)...)
        res[i, j] = fn((i, j), x)
    end
    res
end

function early_lower(fn::Function, ::D.EdgeField, adj::Adjacency)
    res = typeof(adj)()
    for (src, sub) in adj
        s = typeof(sub)()
        for (tgt, x) in sub
            s[tgt] = fn((src, tgt), x)
        end
        res[src] = s
    end
    res
end

#-------------------------------------------------------------------------------------------
# Late check.
# Take this opportunity to lower into a linearized vector.

const EdgeMRef = Tuple{MRef,MRef}

# Extension point.
late_check(::Model, ::D.EdgeField, x, ::EdgeMRef) = x

# Guard the above to upgrade exceptions.
_late_check(md::Model, d::D.EdgeField, x, mref::EdgeMRef) =
    try
        late_check(md, d, x, mref)
    catch e
        e isa LibError || rethrow(e)
        if !(e isa CheckError)
            e = CheckError(e)
        end
        e.ref = ModelRef(mref)
        rethrow(e)
    end

# When obtaining a raw vector.
function late_check(md::Model, d::D.EdgeField, vec::Vector)
    # Check plain number of provided values.
    wb = N.web(md, d)
    exp, act = N.n_edges(wb), length(vec)
    if exp != act
        _, s, are = nsa(exp)
        checkerr(vec, "There $are $exp edge$s to valuate, but the vector is of size $act.")
    end
    # Then check values one by one.
    tp = wb.topology
    src, tgt = N.sides(md, d)
    map(zip(N.edges(tp), vec)) do ((i, j), x)
        a, b = N.to_label.((src.index, tgt.index), (i, j))
        _late_check(md, d, x, ((i, a), (j, b)))
    end
end

# When obtaining a matrix.
function late_check(md::Model, d::D.EdgeField, mat::AbstractMatrix)
    # Check dimensions.
    (src, tgt) = N.web(md, d), N.sides(md, d)
    exp, act = length.((src, tgt)), size(mat)
    if exp != act
        (ns, ss), (nt, st) = NF.ns.(exp)
        checkerr(mat,
            "There are $ns source$ss and $nt target$st, \
             but the matrix received is of size $act.")
    end
    # Then check values one by one as we lower into a linear vector.
    late_lower(md, d, mat)
end

# When obtaining an adjacency list.
late_check(md::Model, d::D.EdgeField, mat::Adjacency) = late_lower(md, d, mat)

# No topology check required for dense matrices.
function late_lower(md::Model, d::D.EdgeField, mat::Matrix)
    (src, tgt) = N.sides(md, d)
    map(pairs(mat)) do (ij, x) # Column-major as expected.
        (i, j) = tuple(ij)
        a, b = N.to_label.((src.index, tgt.index), (i, j))
        _late_check(md, d, x, ((i, a), (i, b)))
    end
end

# Topology check required for sparse data structures.
# TODO: this should not check for completeness on mutation pipeline, right?
# And then it should not even lower to a vector :|
function late_lower(md::Model, d::D.EdgeField, data::Union{SparseMatrix,Adjacency})
    tp = N.web(md, d).topology
    T = D.type(d)
    res = sizehint!(T[], N.n_edges(tp))
    for (exp, act) in zip_exp_act(tp, data)
        miss = if act === MissingEdge
            true # Missing edge.
        elseif exp === MissingEdge
            false # Unexpected edge.
        else
            (act, x) = act
            if exp == act
                # Ok, received as expected.
                push!(res, x)
                continue
            else
                exp < act # Missing if 'act' went further.
            end
        end
        if miss
            (i, j) = exp
            f = D.field(d)
            expl = explicit_null(data, f, i, j)
            checkerr(spm,
                "Missing (structural) edge value. To explicitly make it null, \
                 try something along $black`$expl`$reset (or equivalent).";
                d, mref = to_mref((i, j), md, d))
        else
            (i, j, x) = act
            w = D.web(d)
            checkerr(x,
                "Received unexpected edge value: there is no such $green$w$reset edge.";
                d, mref = to_mref((i, j), md, d))
        end
    end
    res
end

# Iterate both expected and actual edges at the same time to compare topologies.
zip_exp_act(tp::N.Topology, spm::SparseMatrix) =
    zip_longest(N.edges(tp), zip(findnz(spm)...); default = MissingEdge)
zip_exp_act(tp::N.Topology, adj::Adjacency) =
    zip_longest(N.edges(tp), iter(adj); default = MissingEdge)

# Have this private to future-proof against collisions.
struct MissingEdge end

explicit_null(::SparseMatrix, f, i, j) = "$f[$i, $j] = 0"
explicit_null(::Adjacency, f, src, tgt) = "$f[$(repr(src))][$(repr(tgt))] = 0"

# ==========================================================================================
# Expand.

# Data should have already been lowered to the correct vector at this point.
function expand!(md::Model, d::D.EdgeField, vec::Vector)
    wb, f = N.web(md, d), D.field(d)
    N.add_field!(wb, f, vec)
end

# Except for flat values. Lower then.
function expand!(md::Model, d::D.EdgeField, flat)
    n = N.n_edges(N.web(md, d))
    vec = fill(flat, n)
    epand!(md, d, vec)
end

# If not, then just trust whoever only lowered to a matrix yet.
function lower(md::Model, d::D.EdgeField, mat::AbstractMatrix)
    D.is_dense(d) && return mat[:]
    mat isa SparseMatrix && return nonzeros(mat)
    tp = N.web(md, d).topology
    [mat[i, j] for (i, j) in N.edges(tp)]
end

#-------------------------------------------------------------------------------------------
# Obtain.

function obtain(vw::V.EdgeFieldView, (a, b)::Tuple{Ref,Ref})
    wb = N.web(vw)
    tp = wb.topology
    i, j = N.to_index.(N.sides(wb), (a, b))
    i_raw = N.edge(tp, i, j)
    read(N.entry(vw)) do data
        data[i_raw]
    end
end

# ==========================================================================================
#  Mutate.

#-------------------------------------------------------------------------------------------
# Convert RHS.

function convert(d::D.EdgeField, input)
    T = D.type(d)
    Mat = D.is_dense(d) ? Matrix : SparseMatrix
    try_convert(input, T, Vector{T}, Mat{T}, Adjacency{T})
end

#-------------------------------------------------------------------------------------------
# Target whole data the "reassign-like".

# Complete.
function mutate!(md::Model, d::D.EdgeField, ::WholeData, raw) # (vec or flat)
    N.mutate!(N.entry(md, d)) do edges
        edges .= raw
    end
end

# Maybe incomplete.
function mutate!(md::Model, d::D.EdgeField, ::WholeData, adj::Adjacency)
    tp = N.web(md, d).topology
    src, tgt = map(s -> s.index, N.sides(md, d))
    N.mutate!(N.entry(md, d)) do edges
        for (s, t, x) in iter(adj)
            i = N.edge(tp, N.to_index.((src, tgt), (s, t)))
            edges[i] = x
        end
    end
end

# ==========================================================================================
# Display.

function edges_shortline(io::IO, md::Model, d::D.EdgeField)
    cc, fc, rs = F.component_color, F.field_color, reset
    Field = D.CamelCaseSingular(d)
    n, s = N.web(md, d).topology |> N.n_edges |> ns
    N.read(N.entry(md, d)) do data
        min, max = extrema(data)
        vals = min == max ? "$min" : "$min to $max"
        print(io, "$cc$Field$rs: $fc$vals$rs ($fc$n$rs value$s).")
    end
end
