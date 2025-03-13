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
#
# Any kind of input is allowed, making these "parsers" very non-type-stable.
# (call it "parsing" but input is really *julia values*)
# Input is an(y) iterable of (ref, value) pairs for maps,
# with values elided in the binary case.
# References may be grouped together, as an iterable of references instead.
# For adjacency lists, values are maps themselves,
# and grouping references can also happen with values on the lhs,
# rhs being just a list of "target" references.
#
# Here is how we parse each toplevel input pair: (lhs, rhs).
# Call 'strong' end the side of this pair that is holding the value(s),
# and 'weak' end the other side, without the value(s).
# Either side is also either grouped or plain:
#         |  weak      |   strong
#   plain | ref        |   ref => value
#   group | [ref, ref] |  [ref => value, ref => value]
#
# The strategy is to diagnose each side separately,
# attempting to parse as either category,
# asking "forgiveness rather than permission".
# During this diagnosis, normalize any 'plain' input to a (grouped,) input.

# Use this type to hold all temporary status required
# during input parsing, especially useful for quality reporting in case of invalid input.
# This struct is very type-unstable so as to be used for target conversion.
mutable struct Parser
    # Useful if known by callers for some reason.
    expected_R::Option{Type}
    target_type::Function # R -> type.

    # If the above is unset, infer the expected ref type from the first ref parsed.
    found_first_ref::Bool
    first_ref::Option{Any}

    # Locate currently parsed piece of input like [1, :left, 2, :right]..
    path::Vector{Union{Int,Symbol}}

    # Only fill after checking for consistency, duplications etc.
    result::Union{Nothing,Map,BinMap,Adjacency,BinAdjacency}
    Parser(expected_R, target_type, found_first_ref, first_ref) =
        new(expected_R, target_type, found_first_ref, first_ref, [], nothing)
    Parser(expected_R, target_type) = Parser(expected_R, target_type, false, nothing)
end

set_if_first!(p::Parser, ref) =
    if !p.found_first_ref
        p.first_ref = ref
        p.found_first_ref = true
    end

first_ref(p::Parser) =
    if p.found_first_ref
        p.first_ref
    else
        argerr("Undefined first reference: this is a bug in the package.")
    end

Base.push!(p::Parser, ref) = push!(p.path, ref)
Base.pop!(p::Parser) = pop!(p.path)
update!(p::Parser, ref) = p.path[end] = ref
bump!(p::Parser) = p.path[end] += 1
path(p::Parser) = "[$(join(repr.(p.path), "]["))]"

# /!\ possibly long: only include at the end of messages.
function report(p::Parser, input)
    at = isempty(p.path) ? "" : " at $(path(p))"
    "$at: $(repr(input)) ::$(typeof(input))"
end

# Reference type cannot be inferred if input is empty.
# Default to labels because they are stable in case of nodes deletions.
default_R(p::Parser) = isnothing(p.expected_R) ? Symbol : p.expected_R
empty_result(p::Parser) = p.target_type(default_R())()

# Retrieve underlying result, constructing it from inferred/expected R if unset yet.
function result!(p::Parser)
    isnothing(p.result) || return p.result
    R = if p.found_first_ref
        typeof(first_ref(p))
    elseif !isnothing(p.expected_R)
        p.expected_R
    else
        argerr("Cannot construct result without R being inferred: \
                this is a bug in the package.")
    end
    p.result = p.target_type(R)()
end

duperr(p::Parser, ref) = argerr("Duplicated reference$(report(p, ref)).")

#-------------------------------------------------------------------------------------------
# Parsing blocks.

parse_iterable(p::Parser, input, what) =
    try
        iterate(input)
    catch
        argerr("Input for $what needs to be iterable.\n\
                Received$(report(p, input))", rethrow)
    end

parse_pair(p::Parser, input, what) =
    try
        lhs, rhs = input
        # Note that [1, 2, 3] would become (1, 2): raise an error instead.
        try
            _1, _2, _3 = input # That shouldn't work with a true "pair".
            throw("more than 2 values in pair parsing input")
        catch
        end
        return lhs, rhs
    catch
        argerr("Not a `$what` pair$(report(p, input)).")
    end

function parse_ref!(p::Parser, input, what)
    (ref, R, ok) = try
        (graphdataconvert(Symbol, input), Symbol, true)
    catch
        try
            (graphdataconvert(Int, input), Int, true)
        catch
            (nothing, nothing, false)
        end
    end
    ok || argerr("Cannot interpret $what reference \
                  to integer index or symbol label: \
                  received$(report(p, input))")
    if !isnothing(p.expected_R)
        R == p.expected_R || argerr("Invalid $what reference type. \
                                     Expected $(repr(p.expected_R)) (or convertible). \
                                     Received instead$(report(p, input)).")
    end
    set_if_first!(p, ref)
    fR = typeof(first_ref(p))
    if R != fR
        a_ref = (R) -> "$(R == Symbol ? "a label" : "an index") ($R)"
        argerr("The $what reference type for this input \
                was first inferred to be $(a_ref(fR)) \
                based on the received '$(first_ref(p))', \
                but $(a_ref(R)) is found now$(report(p, ref)).")
    end
    ref
end

#-------------------------------------------------------------------------------------------
# Parse into binary maps.

function graphdataconvert(
    ::Type{BinMap{<:Any}},
    input;
    # Use if known somehow.
    ExpectedRefType = nothing,
    # Use if called as a parsing block from another function in this module.
    parser = nothing,
)
    p = isnothing(parser) ? Parser(ExpectedRefType, R -> BinMap{R}) : parser
    it = parse_iterable(p, input, "binary map")
    isnothing(it) && return empty_result(p)

    push!(p, 1)
    while !isnothing(it)
        ref, it = it
        ref = parse_ref!(p, ref, "node")
        res = result!(p)
        ref in res && duperr(p, ref)
        push!(res, ref)
        it = iterate(input, it)
        bump!(p)
    end

    result!(p)
end

#-------------------------------------------------------------------------------------------
# Parse into general maps.
# HERE: keep going.

function graphdataconvert(
    ::Type{Map{<:Any,T}},
    input;
    ExpectedRefType = nothing, # Use if somehow imposed by the calling context.
    first_ref = nothing, # Useful for reporting.
) where {T}
    applicable(iterate, input) || argerr("Ref-value mapping input needs to be iterable.")
    it_pairs = iterate(input)

    if isnothing(it_pairs)
        R = isnothing(ExpectedRefType) ? Symbol : ExpectedRefType
        return Map{R,T}()
    end

    if isnothing(first_ref)
        first_ref = (Ref{Any}(nothing), Ref(false))
    end

    # If there is a first element, use it to infer ref type.
    pair, it_pairs = it_pairs
    refs, value = checked_pair_split(pair, true)
    refs = to_grouped_refs(refs)
    it_refs = iterate(refs)
    isnothing(it_refs) && argerr("No reference received for value: $(repr(pair)).")
    ref, _ = it_refs
    R = checked_ref_type(ref, ExpectedRefType, first_ref)
    res = Map{R,T}()
    for ref in refs
        ref, value = checked_pair_convert((R, T), (ref, value))
        res[ref] = value
    end

    # Then fill up the map.
    it_pairs = iterate(input, it_pairs)
    while !isnothing(it_pairs)
        pair, it_pairs = it_pairs
        refs, value = checked_pair_split(pair, true)
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

# The binary case *can* accept boolean masks.
function graphdataconvert(
    ::Type{BinMap{<:Any}},
    input::AbstractVector{Bool};
    ExpectedRefType = Int,
)
    res = BinMap{ExpectedRefType}()
    for (i, val) in enumerate(input)
        val && push!(res, i)
    end
    res
end

function graphdataconvert(
    ::Type{BinMap{<:Any}},
    input::AbstractSparseVector{Bool,R};
    ExpectedRefType = R,
) where {R}
    res = BinMap{ExpectedRefType}()
    for ref in findnz(input)[1]
        push!(res, ref)
    end
    res
end

#-------------------------------------------------------------------------------------------
# Similar, nested logic for adjacency maps.

function graphdataconvert(
    ::Type{Adjacency{<:Any,T}},
    input;
    ExpectedRefType = nothing,
) where {T}
    applicable(iterate, input) || argerr("Adjacency list input needs to be iterable.")
    it = iterate(input)
    if isnothing(it)
        R = isnothing(ExpectedRefType) ? Int : ExpectedRefType
        return Adjacency{R,T}()
    end

    pair, it = it
    lhs, rhs = checked_pair_split(pair, false)

    first_ref = (Ref{Any}(nothing), Ref(false))

    lhs, rhs = map((lhs, rhs)) do side
        determined = false
        safe_first_ref = deepcopy(first_ref)
        (is_strong_group, strong_group, R_strong_group) = try
            # Attempt to parse as a submap, only successful for strong groups.
            sub = graphdataconvert((@GraphData {Map}{T}), side; ExpectedRefType, first_ref)
            (true, sub, reftype(sub))
        catch e
            first_ref = safe_first_ref # Restore if failed.
            (false, e, nothing)
        end
        determined |= is_strong_group
        (is_weak_group, weak_group, R_weak_group) = if !determined
            # Attempt to as a sub-binmap, only successful for weak groups.
            try
                sub = graphdataconvert(
                    (@GraphData {Map}{:bin}),
                    side;
                    ExpectedRefType,
                    first_ref,
                )
                (true, sub, reftype(sub))
            catch e
                first_ref = safe_first_ref # Restore if failed.
                (false, e, nothing)
            end
        else
            (false, nothing, nothing)
        end
        determined |= is_weak_group
        # Only plain options remain, but group them to normalize.
        (is_weak_plain, group, R_weak_plain) = if !is_strong_group && !is_weak_group
            try
                R = infer_ref_type(side)
                set_if_first_ref!(first_ref, side)
                (true, (side,), R)
            catch e
                (false, e, nothing)
            end
        else
            (false, nothing, nothing)
        end
        determined |= is_weak_plain
        (is_strong_plain, group, R_strong_plain) = if !determined
            ref, value = checked_pair_split(side, true)
            R = checked_ref_type(ref, ExpectedRefType, first_ref)
            set_if_first_ref!(first_ref, ref)
            (true, (ref => value,), R)
        else
            (false, group, nothing)
        end
        (;
            is_strong_group,
            strong_group,
            R_strong_group,
            is_weak_group,
            weak_group,
            R_weak_group,
            is_weak_plain,
            group,
            R_weak_plain,
            is_strong_plain,
            R_strong_plain,
        )
    end

    display(input)
    display(OrderedDict(pairs(lhs)))
    display(OrderedDict(pairs(rhs)))
    display(first_ref)
    error("STOP HERE")

    (strong_grouped_sources, strong_grouped_lhs_R, is_lhs_strong_grouped),
    (strong_grouped_targets, strong_grouped_rhs_R, is_rhs_strong_grouped) =
        map((lhs, rhs)) do side
            try
                sub = submap((@GraphData {Map}{T}), side, ExpectedRefType)
                (sub, reftype(sub), true)
            catch e
                (e, nothing, false)
            end
        end
    ((weak_sources, weak_lhs), (weak_targets, weak_rhs)) = map((
        (lhs, is_rhs_strong_grouped),
        (rhs, is_lhs_strong_grouped),
    )) do (side, is_other_strong_grouped)
        if is_other_strong_grouped
            try
                R = infer_ref_type(side)
                ((side,), true, R)
            catch _
            end
        end
    end

    (is_lhs_strong_grouped && is_rhs_strong_grouped) &&
        argerr("Cannot provide values for both sources and targets in adjacency input.\n\
                Received LHS: $(repr(lhs))\n\
                Received RHS: $(repr(rhs))")


    key, value = checked_pair_split(pair)
    R = checked_ref_type(key, ExpectedRefType, key, first_ref)
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

function graphdataconvert(::Type{BinAdjacency{<:Any}}, input; ExpectedRefType = nothing)
    applicable(iterate, input) ||
        argerr("Binary adjacency list input needs to be iterable.")
    it = iterate(input)
    if isnothing(it)
        R = isnothing(ExpectedRefType) ? Int : ExpectedRefType
        return BinAdjacency{R}()
    end

    first_ref = (Ref{Any}(nothing), Ref(false))

    # Type inference from first element.
    pair, it = it
    key, value = checked_pair_split(pair)
    R = checked_ref_type(key, ExpectedRefType, first_ref)
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
    ExpectedRefType = Int,
)
    res = BinAdjacency{ExpectedRefType}()
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
    ExpectedRefType = R,
) where {R}
    res = BinAdjacency{ExpectedRefType}()
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
graphdataconvert(::Type{Map{<:Any,T}}, input::Map{Int,T}) where {T} = input
graphdataconvert(::Type{BinMap{<:Any}}, input::BinMap{Int}) = input
graphdataconvert(::Type{BinMap{<:Any}}, input::BinMap{Symbol}) = input
graphdataconvert(::Type{Adjacency{<:Any,T}}, input::Adjacency{Symbol,T}) where {T} = input
graphdataconvert(::Type{Adjacency{<:Any,T}}, input::Adjacency{Int,T}) where {T} = input
graphdataconvert(::Type{BinAdjacency{<:Any}}, input::BinAdjacency{Symbol}) = input
graphdataconvert(::Type{BinAdjacency{<:Any}}, input::BinAdjacency{Int}) = input

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

# Normalize ungrouped refs into iterable singleton refs group.
to_grouped_refs(refs) =
    if applicable(iterate, refs) && !(refs isa Integer)
        refs
    else
        (refs,)
    end

checked_value_convert(T, value, ref) =
    try
        graphdataconvert(T, value)
    catch
        argerr("Map value at ref '$ref' cannot be converted to '$(T)': \
                received $(repr(value)) ::$(typeof(value)).")
    end

checked_pair_convert((R, T), (ref, value)) =
    (checked_ref_convert(R, ref), checked_value_convert(T, value, ref))

submap(::Type{M}, input, R, ref) where {M<:Map} =
    try
        graphdataconvert(M, input; ExpectedRefType = R)
    catch
        if isnothing(ref)
            argerr("Error while parsing sources as adjacency list input \
                    (see further down the stacktrace).")
        else
            argerr("Error while parsing adjacency list input at ref '$ref' \
                    (see further down the stacktrace).")
        end
    end
# Special binary case allows scalar refs to be directly used instead of singleton.
function submap(::Type{BM}, input, R, ref) where {BM<:BinMap}
    typeof(input) == R && (input = [input]) # Convert scalar ref to singleton ref.
    try
        graphdataconvert(BM, input; ExpectedRefType = R)
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
