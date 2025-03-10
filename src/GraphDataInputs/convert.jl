# Convenience explicit conversion to the given union type from constructor arguments.

# The conversions allowed.
graphdataconvert(::Type{T}, source::T) where {T} = source # Trivial identity.

# ==========================================================================================
# Scalar conversions.
macro allow_convert(Source, Target, f)
    esc(quote
        graphdataconvert(::Type{$Target}, v::$Source) = $f(v)
    end)
end
#! format: off
@allow_convert Symbol         String  String
@allow_convert Char           String  (c -> "$c")
@allow_convert AbstractString Symbol  Symbol
@allow_convert Char           Symbol  Symbol
#! format: on

# ==========================================================================================
# Simple collections conversions.

macro allow_convert_all(Source, Target)
    esc(
        quote
        #! format: off
        @allow_convert $Source                 $Target               $Target
        @allow_convert Vector{<:$Source}       Vector{$Target}       Vector{$Target}
        @allow_convert Matrix{<:$Source}       Matrix{$Target}       Matrix{$Target}
        @allow_convert SparseVector{<:$Source} SparseVector{$Target} SparseVector{$Target}
        @allow_convert SparseMatrix{<:$Source} SparseMatrix{$Target} SparseMatrix{$Target}

        @allow_convert(
            Vector{<:$Source},
            SparseVector{$Target},
            v -> SparseVector{$Target}(sparse(v)),
        )
        @allow_convert(
            Matrix{<:$Source},
            SparseMatrix{$Target},
            m -> SparseMatrix{$Target}(sparse(m)),
        )

        # Don't shadow the identity case, which should return an alias of the input.
        @allow_convert $Target               $Target               identity
        @allow_convert Vector{$Target}       Vector{$Target}       identity
        @allow_convert Matrix{$Target}       Matrix{$Target}       identity
        @allow_convert SparseVector{$Target} SparseVector{$Target} identity
        @allow_convert SparseMatrix{$Target} SparseMatrix{$Target} identity
        #! format: on

        end,
    )
end

@allow_convert_all Real Float64
@allow_convert_all Integer Int64
@allow_convert_all Integer Bool

# ==========================================================================================
# Map/Adjacency conversions.

# Mappings accept any valid incoming collection
# (very non-type-stable: only meant for direct user-facing APIs)
function graphdataconvert(
    ::Type{Map{<:Any,T}},
    input;
    ExpectedRefType = nothing, # Use if somehow imposed by the calling context.
) where {T}
    applicable(iterate, input) || argerr("Ref-value mapping input needs to be iterable.")
    it_pairs = iterate(input)

    # Reference type cannot be inferred if input is empty.
    # Default to labels because they are stable in case of nodes deletions.
    if isnothing(it_pairs)
        R = isnothing(ExpectedRefType) ? Symbol : ExpectedRefType
        return Map{R,T}()
    end

    # If there is a first element, use it to infer ref type.
    pair, it_pairs = it_pairs
    refs, value = checked_pair_split(pair)
    refs = to_grouped_refs(refs)
    it_refs = iterate(refs)
    isnothing(it_refs) && argerr("No reference received for value: $(repr(pair)).")
    first_ref, _ = it_refs
    R = infer_ref_type(first_ref)
    check_ref_type(R, ExpectedRefType, first_ref)
    res = Map{R,T}()
    for ref in refs
        ref, value = checked_pair_convert((R, T), (ref, value))
        res[ref] = value
    end

    # Then fill up the map.
    it_pairs = iterate(input, it_pairs)
    while !isnothing(it_pairs)
        pair, it_pairs = it_pairs
        refs, value = checked_pair_split(pair)
        refs = to_grouped_refs(refs)
        (value, invalid_value) = try
            (checked_value_convert(T, value, refs), false)
        catch e
            (e, true) # Hold error until we've parsed the refs for better reporting.
        end
        for ref in refs
            ref = checked_ref_convert(R, ref)
            haskey(res, ref) && duperr(ref)
            invalid_value && rethrow(value)
            res[ref] = value
        end
        it_pairs = iterate(input, it_pairs)
    end
    res
end

# Special binary case.
function graphdataconvert(::Type{BinMap{<:Any}}, input; expected_I = nothing)
    applicable(iterate, input) || argerr("Binary mapping input needs to be iterable.")
    it = iterate(input)
    if isnothing(it)
        R = isnothing(expected_I) ? Int64 : expected_I
        return BinMap{R}()
    end

    # Type inference from first element.
    key, it = it
    R = infer_ref_type(key)
    check_ref_type(R, expected_I, key)
    key = checked_ref_convert(R, key)
    res = BinMap{R}()
    push!(res, key)

    # Fill up the set.
    it = iterate(input, it)
    while !isnothing(it)
        key, it = it
        key = checked_ref_convert(R, key)
        key in res && duperr(key)
        push!(res, key)
        it = iterate(input, it)
    end
    res
end

# The binary case *can* accept boolean masks.
function graphdataconvert(
    ::Type{BinMap{<:Any}},
    input::AbstractVector{Bool};
    expected_I = Int64,
)
    res = BinMap{expected_I}()
    for (i, val) in enumerate(input)
        val && push!(res, i)
    end
    res
end

function graphdataconvert(
    ::Type{BinMap{<:Any}},
    input::AbstractSparseVector{Bool,R};
    expected_I = R,
) where {R}
    res = BinMap{expected_I}()
    for i in findnz(input)[1]
        push!(res, i)
    end
    res
end

#-------------------------------------------------------------------------------------------
# Similar, nested logic for adjacency maps.

function graphdataconvert(::Type{Adjacency{<:Any,T}}, input; expected_I = nothing) where {T}
    applicable(iterate, input) || argerr("Adjacency list input needs to be iterable.")
    it = iterate(input)
    if isnothing(it)
        R = isnothing(expected_I) ? Int64 : expected_I
        return Adjacency{R,T}()
    end

    # Treat values as regular maps.
    pair, it = it
    key, value = checked_pair_split(pair)
    R = infer_ref_type(key)
    check_ref_type(R, expected_I, key)
    key = checked_ref_convert(R, key)
    value = submap((@GraphData {Map}{T}), value, R, key)
    res = Adjacency{R,T}()
    res[key] = value

    # Fill up the list.
    it = iterate(input, it)
    while !isnothing(it)
        pair, it = it
        key, value = checked_pair_split(pair)
        key = checked_ref_convert(R, key)
        value = submap((@GraphData {Map}{T}), value, R, key)
        haskey(res, key) && duperr(key)
        res[key] = value
        it = iterate(input, it)
    end
    res
end

function graphdataconvert(::Type{BinAdjacency{<:Any}}, input; expected_I = nothing)
    applicable(iterate, input) ||
        argerr("Binary adjacency list input needs to be iterable.")
    it = iterate(input)
    if isnothing(it)
        R = isnothing(expected_I) ? Int64 : expected_I
        return BinAdjacency{R}()
    end

    # Type inference from first element.
    pair, it = it
    key, value = checked_pair_split(pair)
    R = infer_ref_type(key)
    check_ref_type(R, expected_I, key)
    key = checked_ref_convert(R, key)
    value = submap((@GraphData {Map}{:bin}), value, R, key)
    res = BinAdjacency{R}()
    res[key] = value

    # Fill up the set.
    it = iterate(input, it)
    while !isnothing(it)
        pair, it = it
        key, value = checked_pair_split(pair)
        key = checked_ref_convert(R, key)
        value = submap((@GraphData {Map}{:bin}), value, R, key)
        haskey(res, key) && duperr(key)
        res[key] = value
        it = iterate(input, it)
    end
    res
end

# The binary case *can* accept boolean matrices.
function graphdataconvert(
    ::Type{BinAdjacency{<:Any}},
    input::AbstractMatrix{Bool},
    expected_I = Int64,
)
    res = BinAdjacency{expected_I}()
    for (i, row) in enumerate(eachrow(input))
        adj_line = BinMap(j for (j, val) in enumerate(row) if val)
        isempty(adj_line) && continue
        res[i] = adj_line
    end
    res
end

function graphdataconvert(
    ::Type{BinAdjacency{<:Any}},
    input::AbstractSparseMatrix{Bool,R},
    expected_I = R,
) where {R}
    res = BinAdjacency{expected_I}()
    nzi, nzj, _ = findnz(input)
    for (i, j) in zip(nzi, nzj)
        if haskey(res, i)
            push!(res[i], j)
        else
            res[i] = BinMap([j])
        end
    end
    res
end

# Alias if types matches exactly.
graphdataconvert(::Type{Map{<:Any,T}}, input::Map{Symbol,T}) where {T} = input
graphdataconvert(::Type{Map{<:Any,T}}, input::Map{Int64,T}) where {T} = input
graphdataconvert(::Type{BinMap{<:Any}}, input::BinMap{Int64}) = input
graphdataconvert(::Type{BinMap{<:Any}}, input::BinMap{Symbol}) = input
graphdataconvert(::Type{Adjacency{<:Any,T}}, input::Adjacency{Symbol,T}) where {T} = input
graphdataconvert(::Type{Adjacency{<:Any,T}}, input::Adjacency{Int64,T}) where {T} = input
graphdataconvert(::Type{BinAdjacency{<:Any}}, input::BinAdjacency{Symbol}) = input
graphdataconvert(::Type{BinAdjacency{<:Any}}, input::BinAdjacency{Int64}) = input

#-------------------------------------------------------------------------------------------
# Extract binary maps/adjacency from regular ones.
function graphdataconvert(::Type{BinMap}, input::Map{R}) where {R}
    res = BinMap{R}()
    for (k, _) in input
        push!(res, k)
    end
    res
end
function graphdataconvert(::Type{BinAdjacency{<:Any}}, input::Adjacency{R}) where {R}
    res = BinAdjacency{R}()
    for (i, sub) in input
        res[i] = graphdataconvert(BinMap, sub)
    end
    res
end

#-------------------------------------------------------------------------------------------
# Conversion helpers.

duperr(ref) = argerr("Duplicated reference: $(repr(ref)).")

function infer_ref_type(ref)
    applicable(graphdataconvert, Int64, ref) && return Int64
    applicable(graphdataconvert, Symbol, ref) && return Symbol
    argerr("Cannot convert reference to integer index or symbol label: \
            received $(repr(ref)) ::$(typeof(ref)).")
end

# Normalize ungrouped refs into iterable singleton refs group.
to_grouped_refs(refs) =
    if applicable(iterate, refs) && !(refs isa Integer)
        refs
    else
        (refs,)
    end

check_ref_type(R, ExpectedRefType, first_ref) =
    isnothing(ExpectedRefType) ||
    R == ExpectedRefType ||
    argerr("Expected '$ExpectedRefType' as node reference types, got '$R' instead \
            (inferred from first ref: $(repr(first_ref)) ::$(typeof(first_ref))).")

checked_ref_convert(R, ref) =
    try
        graphdataconvert(R, ref)
    catch
        argerr("Map reference cannot be converted to '$(R)': \
                received $(repr(ref)) ::$(typeof(ref)).")
    end

checked_value_convert(T, value, ref) =
    try
        graphdataconvert(T, value)
    catch
        argerr("Map value at ref '$ref' cannot be converted to '$(T)': \
                received $(repr(value)) ::$(typeof(value)).")
    end

# "Better ask forgiveness than permission".. is that also julian?
checked_pair_split(pair) =
    try
        ref, value = pair
        return ref, value
    catch
        argerr("Not a (node reference, value) pair: $(repr(pair)) ::$(typeof(pair)).")
    end

checked_pair_convert((R, T), (ref, value)) =
    (checked_ref_convert(R, ref), checked_value_convert(T, value, ref))

submap(::Type{M}, input, R, ref) where {M<:Map} =
    try
        graphdataconvert(M, input; expected_I = R)
    catch
        argerr("Error while parsing adjacency list input at ref '$ref' \
                (see further down the stacktrace).")
    end
# Special binary case allows scalar refs to be directly used instead of singleton.
function submap(::Type{BM}, input, R, ref) where {BM<:BinMap}
    typeof(input) == R && (input = [input]) # Convert scalar ref to singleton ref.
    try
        graphdataconvert(BM, input; expected_I = R)
    catch
        argerr("Error while parsing adjacency list input at ref '$ref' \
                (see further down the stacktrace).")
    end
end

# ==========================================================================================
# Convenience macro.

# Example usage:
#   @tographdata var {Sym, Scal, SpVec}{Float64}
#   @tographdata var YSN{Float64}
macro tographdata(var::Symbol, input)
    @defloc
    tographdata(loc, var, input)
end
function tographdata(loc, var, input)
    @capture(input, types_{Target_} | types_{})
    isnothing(types) && argerr("Invalid @tographdata target types at $loc.\n\
                                Expected @tographdata var {aliases...}{Target}. \
                                Got $(repr(input)).")
    targets = parse_types(loc, types, Target)
    targets = Expr(:vect, targets...)
    vsym = Meta.quot(var)
    var = esc(var)
    :(_tographdata($vsym, $var, $targets))
end
function _tographdata(vsym, var, targets)
    # Try all conversions, first match first served.
    for Target in targets
        if applicable(graphdataconvert, Target, var)
            try
                return graphdataconvert(Target, var)
            catch
                if Target <: Adjacency
                    T = Target.body.parameters[2].parameters[2]
                    Target = "adjacency list for '$T' data"
                elseif Target <: BinAdjacency
                    Target = "binary adjacency list"
                elseif Target <: Map
                    T = Target.body.parameters[2]
                    Target = "ref-value map for '$T' data"
                elseif Target <: BinMap
                    Target = "binary ref-value map"
                end
                argerr("Error while attempting to convert \
                        '$vsym' to $Target \
                        (details further down the stacktrace). \
                        Received $(repr(var)) ::$(typeof(var)).")
            end
        end
    end
    targets =
        length(targets) == 1 ? "$(first(targets))" : "either $(join(targets, ", ", " or "))"
    argerr("Could not convert '$vsym' to $targets. \
            The value received is $(repr(var)) ::$(typeof(var)).")
end
export @tographdata

# Convenience to re-bind in local scope, avoiding the akward following pattern:
#   long_var_name = @tographdata long_var_name <...>
# In favour of:
#   @tographdata! long_var_name <...>
macro tographdata!(var::Symbol, input)
    @defloc
    evar = esc(var)
    :($evar = $(tographdata(loc, var, input)))
end
export @tographdata!
