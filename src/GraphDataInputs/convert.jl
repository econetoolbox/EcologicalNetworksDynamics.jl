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

# Mappings accept any valid incoming collection (very non-type-stable, right?).
function graphdataconvert(
    ::Type{Map{<:Any,T}},
    input;
    expected_I = nothing, # Use if somehow imposed by the calling context.
) where {T}
    applicable(iterate, input) || argerr("Key-value mapping input needs to be iterable.")
    it = iterate(input)

    # Key type cannot be inferred if input is empty. Arbitrary default to integers.
    if isnothing(it)
        I = isnothing(expected_I) ? Int64 : expected_I
        return Map{I,T}()
    end

    # If there is a first element, use it to infer key type.
    pair, it = it
    key, value = checked_pair_split(pair)
    I = infer_key_type(key)
    check_key_type(I, expected_I, key)
    key, value = checked_pair_convert((I, T), (key, value))
    res = Map{I,T}()
    res[key] = value

    # Then fill up the map.
    it = iterate(input, it)
    while !isnothing(it)
        pair, it = it
        key, value = checked_pair_convert((I, T), checked_pair_split(pair))
        haskey(res, key) && duperr(key)
        res[key] = value
        it = iterate(input, it)
    end
    res
end

# Special binary case.
function graphdataconvert(::Type{BinMap{<:Any}}, input; expected_I = nothing)
    applicable(iterate, input) || argerr("Binary mapping input needs to be iterable.")
    it = iterate(input)
    if isnothing(it)
        I = isnothing(expected_I) ? Int64 : expected_I
        return BinMap{I}()
    end

    # Type inference from first element.
    key, it = it
    I = infer_key_type(key)
    check_key_type(I, expected_I, key)
    key = checked_key_convert(I, key)
    res = BinMap{I}()
    push!(res, key)

    # Fill up the set.
    it = iterate(input, it)
    while !isnothing(it)
        key, it = it
        key = checked_key_convert(I, key)
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
    input::AbstractSparseVector{Bool,I};
    expected_I = I,
) where {I}
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
        I = isnothing(expected_I) ? Int64 : expected_I
        return Adjacency{I,T}()
    end

    # Treat values as regular maps.
    pair, it = it
    key, value = checked_pair_split(pair)
    I = infer_key_type(key)
    check_key_type(I, expected_I, key)
    key = checked_key_convert(I, key)
    value = submap((@GraphData {Map}{T}), value, I, key)
    res = Adjacency{I,T}()
    res[key] = value

    # Fill up the list.
    it = iterate(input, it)
    while !isnothing(it)
        pair, it = it
        key, value = checked_pair_split(pair)
        key = checked_key_convert(I, key)
        value = submap((@GraphData {Map}{T}), value, I, key)
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
        I = isnothing(expected_I) ? Int64 : expected_I
        return BinAdjacency{I}()
    end

    # Type inference from first element.
    pair, it = it
    key, value = checked_pair_split(pair)
    I = infer_key_type(key)
    check_key_type(I, expected_I, key)
    key = checked_key_convert(I, key)
    value = submap((@GraphData {Map}{:bin}), value, I, key)
    res = BinAdjacency{I}()
    res[key] = value

    # Fill up the set.
    it = iterate(input, it)
    while !isnothing(it)
        pair, it = it
        key, value = checked_pair_split(pair)
        key = checked_key_convert(I, key)
        value = submap((@GraphData {Map}{:bin}), value, I, key)
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
    input::AbstractSparseMatrix{Bool,I},
    expected_I = I,
) where {I}
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
function graphdataconvert(::Type{BinMap}, input::Map{I}) where {I}
    res = BinMap{I}()
    for (k, _) in input
        push!(res, k)
    end
    res
end
function graphdataconvert(::Type{BinAdjacency{<:Any}}, input::Adjacency{I}) where {I}
    res = BinAdjacency{I}()
    for (i, sub) in input
        res[i] = graphdataconvert(BinMap, sub)
    end
    res
end

#-------------------------------------------------------------------------------------------
# Conversion helpers.

duperr(key) = argerr("Duplicated key: $(repr(key)).")

function infer_key_type(key)
    applicable(graphdataconvert, Int64, key) && return Int64
    applicable(graphdataconvert, Symbol, key) && return Symbol
    argerr("Cannot convert key to integer or symbol label: \
            received $(repr(key)) ::$(typeof(key)).")
end

check_key_type(I, expected_I, first_key) =
    isnothing(expected_I) ||
    I == expected_I ||
    argerr("Expected '$expected_I' as key types, got '$I' instead \
            (inferred from first key: $(repr(first_key)) ::$(typeof(first_key))).")

# "Better ask forgiveness than permission".. is that also julian?
checked_pair_split(pair) =
    try
        key, value = pair
        return key, value
    catch
        argerr("Not a key-value pair: $(repr(pair)) ::$(typeof(pair)).")
    end

checked_key_convert(I, key) =
    try
        graphdataconvert(I, key)
    catch
        argerr("Map key cannot be converted to '$(I)': \
                received $(repr(key)) ::$(typeof(key)).")
    end

checked_value_convert(T, value, key) =
    try
        graphdataconvert(T, value)
    catch
        argerr("Map value at key '$key' cannot be converted to '$(T)': \
                received $(repr(value)) ::$(typeof(value)).")
    end

checked_pair_convert((I, T), (key, value)) =
    (checked_key_convert(I, key), checked_value_convert(T, value, key))

submap(::Type{M}, input, I, key) where {M<:Map} =
    try
        graphdataconvert(M, input; expected_I = I)
    catch
        argerr("Error while parsing adjacency list input at key '$key' \
                (see further down the stacktrace).")
    end
# Special binary case allows scalar keys to be directly used instead of singleton.
function submap(::Type{BM}, input, I, key) where {BM<:BinMap}
    typeof(input) == I && (input = [input]) # Convert scalar key to singleton key.
    try
        graphdataconvert(BM, input; expected_I = I)
    catch
        argerr("Error while parsing adjacency list input at key '$key' \
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
                    Target = "key-value map for '$T' data"
                elseif Target <: BinMap
                    Target = "binary key-value map"
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
