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
    # Nothing for the special binary case.
    T::Option{Type}

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
    Parser(T, R, target_type) = new(T, R, target_type, false, nothing, [], nothing)

    # Useful to fork into a sub-parser.
    Parser(p::Parser, target_type) = new(
        p.T,
        p.expected_R,
        target_type,
        p.found_first_ref,
        p.first_ref,
        deepcopy(p.path),
        nothing,
    )
end
fork(p::Parser, target_type) = Parser(p, target_type)

# Commit to successful fork.
function merge!(a::Parser, b::Parser)
    a.found_first_ref = b.found_first_ref
    a.first_ref = b.first_ref
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
        throw("Undefined first reference: this is a bug in the package.")
    end

Base.push!(p::Parser, ref) = push!(p.path, ref)
Base.pop!(p::Parser) = pop!(p.path)
update!(p::Parser, ref) = p.path[end] = ref
bump!(p::Parser) = p.path[end] += 1
path(p::Parser) = "[$(join(p.path, "]["))]"

# /!\ possibly long: only include at the end of messages.
function report(p::Parser, input)
    at = isempty(p.path) ? "" : " at $(path(p))"
    "$at: $(repr(input)) ::$(typeof(input))"
end

# Reference type cannot be inferred if input is empty.
# Default to labels because they are stable in case of nodes deletions.
default_R(p::Parser) = isnothing(p.expected_R) ? Symbol : p.expected_R
empty_result(p::Parser) = p.target_type(default_R(p))()
get_R(p::Parser) =
    if p.found_first_ref
        typeof(p.first_ref)
    else
        throw("Undetermined reference type: this is a bug in the package.")
    end

# Retrieve underlying result, constructing it from inferred/expected R if unset yet.
function result!(p::Parser)
    isnothing(p.result) || return p.result
    R = if p.found_first_ref
        typeof(first_ref(p))
    elseif !isnothing(p.expected_R)
        p.expected_R
    else
        throw("Cannot construct result without R being inferred: \
                this is a bug in the package.")
    end
    p.result = p.target_type(R)()
end

# Exceptions with this types bubble up through the "forgiveness" pattern.
# Because they are only emitted in situations where the input category
# was considered unambiguous.
struct Interrupt <: Exception
    mess::String
end
Base.showerror(io::IO, e::Interrupt) = print(io, e.mess)
interr(mess, raise = throw) = raise(Interrupt(mess))
duperr(p::Parser, ref) = interr("Duplicated reference$(report(p, ref)).")

#-------------------------------------------------------------------------------------------
# Parsing blocks.

parse_iterable(p::Parser, input, what) =
    try
        iterate(input)
    catch e
        e isa MethodError && argerr(
            "Input for $what needs to be iterable.\n\
             Received$(report(p, input))",
            rethrow,
        )
        rethrow(e)
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

function parse_weak_ref!(p::Parser, input, what)
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
        R == p.expected_R || unexpected_reftype(what, p, input)
    end
    set_if_first!(p, ref)
    fR = typeof(first_ref(p))
    if R != fR
        interr("$(inferred_ref(what, p)), but $(a_ref(R)) is now found$(report(p, ref)).")
    end
    ref
end
# Reused elsewhere.
unexpected_reftype(what, p, input) = interr("Invalid $what reference type. \
                                             Expected $(repr(p.expected_R)) \
                                             (or convertible). \
                                             Received instead$(report(p, input)).")
a_ref(R) = "$(R == Symbol ? "a label" : "an index") ($R)"
inferred_ref(what, p) = "The $what reference type for this input \
                         was first inferred to be $(a_ref(typeof(first_ref(p)))) \
                         based on the received '$(first_ref(p))'"

# If ungrouped, normalize to grouped.
function parse_grouped_refs!(p::Parser, input, what)
    (refs, ok) = try
        f = fork(p, R -> BinMap{R})
        refs = graphdataconvert(
            BinMap{<:Any},
            input;
            parser = f,
            what = (; whole = "grouped references", ref = what),
        )
        merge!(p, f)
        (refs, true)
    catch e
        e isa Interrupt && rethrow(e)
        try
            ref = parse_weak_ref!(p, input, what)
            ((ref,), true)
        catch e
            (e, false)
        end
    end
    ok || throw(refs)
    refs
end

parse_value(p::Parser, input) =
    try
        graphdataconvert(p.T, input)
    catch
        interr(
            "Expected values of type '$(p.T)', received instead$(report(p, input))",
            rethrow,
        )
    end

#-------------------------------------------------------------------------------------------
# Parse binary maps.

function graphdataconvert(
    ::Type{BinMap{<:Any}},
    input;
    ExpectedRefType = nothing,
    # Use if called as a parsing block from another function in this module.
    parser = nothing,
    what = (; whole = "binary map", ref = "node"),
)
    p = isnothing(parser) ? Parser(nothing, ExpectedRefType, R -> BinMap{R}) : parser
    it = parse_iterable(p, input, what.whole)
    isnothing(it) && return empty_result(p)

    push!(p, 1)
    while !isnothing(it)
        ref, it = it
        ref = parse_weak_ref!(p, ref, what.ref)
        res = result!(p)
        ref in res && duperr(p, ref)
        push!(res, ref)
        it = iterate(input, it)
        bump!(p)
    end

    result!(p)
end

# The binary case *can* accept boolean masks.
function graphdataconvert(
    ::Type{BinMap{<:Any}},
    input::AbstractVector{Bool};
    # Match the general case..
    ExpectedRefType = nothing,
    parser = nothing,
    what = (; whole = "binary map"),
)
    # .. although the context is much different:
    # only indices can be retrieved or even *expected* from this kind of input.
    !isnothing(ExpectedRefType) &&
        ExpectedRefType != Int &&
        interr("Label-indexed binary maps cannot be produced from boolean collections.")
    !isnothing(parser) &&
        parser.expected_R != Int &&
        unexpected_reftype(what.whole, parser, input)
    from_boolean_mask(input)
end

function from_boolean_mask(input)
    res = BinMap{Int}()
    for (i, val) in enumerate(input)
        val && push!(res, i)
    end
    res
end

function from_boolean_mask(input::AbstractSparseVector{Bool})
    res = BinMap{Int}()
    for ref in findnz(input)[1]
        push!(res, ref)
    end
    res
end

#-------------------------------------------------------------------------------------------
# Parse general maps.

function graphdataconvert(
    ::Type{Map{<:Any,T}},
    input;
    ExpectedRefType = nothing,
    parser = nothing,
    what = (; whole = "map", pair = "reference(s) => value", ref = "node"),
) where {T}
    p = isnothing(parser) ? Parser(T, ExpectedRefType, R -> Map{R,T}) : parser
    it = parse_iterable(p, input, what)
    isnothing(it) && return empty_result(p)

    push!(p, 1)
    while !isnothing(it)
        pair, it = it
        refs, value = parse_pair(p, pair, what.pair)
        push!(p, :left) # Start left because :right errors may be much uglier.
        refs = parse_grouped_refs!(p, refs, what.ref)
        update!(p, :right)
        value = parse_value(p, value)
        update!(p, :left)
        res = result!(p)
        push!(p, 1)
        for ref in refs
            haskey(res, ref) && duperr(p, ref)
            res[ref] = value
            bump!(p)
        end
        pop!(p)
        pop!(p)
        it = iterate(input, it)
        bump!(p)
    end

    result!(p)
end

#-------------------------------------------------------------------------------------------
# Parse binary adjacency maps.

function graphdataconvert(
    ::Type{BinAdjacency{<:Any}},
    input;
    ExpectedRefType = nothing,
    parser = nothing,
)
    p = isnothing(parser) ? Parser(nothing, ExpectedRefType, R -> BinAdjacency{R}) : parser
    it = parse_iterable(p, input, "binary adjacency map")
    isnothing(it) && return empty_result(p)

    push!(p, 1)
    while !isnothing(it)
        pair, it = it
        sources, targets = parse_pair(p, pair, "source(s) => target(s)")
        push!(p, :left)
        sources = parse_grouped_refs!(p, sources, "source node")
        update!(p, :right)
        targets = parse_grouped_refs!(p, targets, "target node")
        res = result!(p)
        update!(p, :left)
        push!(p, 1)
        pend = (length(p.path)-1):length(p.path)
        for src in sources
            sub = if haskey(res, src)
                res[src]
            else
                res[src] = OrderedSet{get_R(p)}()
            end
            safe = p.path[pend]
            p.path[pend] .= (:right, 1)
            for tgt in targets
                tgt in sub && interr(
                    "Duplicate edge specification \
                     $(repr(src)) → $(repr(tgt))$(report(p, tgt))",
                )
                push!(sub, tgt)
                bump!(p)
            end
            p.path[pend] .= safe
            isempty(sub) && interr("No target provided for source$(report(p, src))")
            bump!(p)
        end
        pop!(p)
        pop!(p)
        it = iterate(input, it)
        bump!(p)
    end

    result!(p)
end

# The binary case *can* accept boolean matrices.
function graphdataconvert(
    ::Type{BinAdjacency{<:Any}},
    input::AbstractMatrix{Bool};
    ExpectedRefType = nothing,
    parser = nothing,
    what = (; whole = "binary map"),
)
    !isnothing(ExpectedRefType) &&
        ExpectedRefType != Int &&
        interr("Label-indexed binary adjacency lists \
                cannot be produced from boolean matrices.")
    !isnothing(parser) &&
        parser.expected_R != Int &&
        unexpected_reftype(what.whole, parser, input)
    from_boolean_matrix(input)
end

function from_boolean_matrix(input)
    res = BinAdjacency{Int}()
    for (i, row) in enumerate(eachrow(input))
        adj_line = BinMap(j for (j, val) in enumerate(row) if val)
        isempty(adj_line) && continue
        res[i] = adj_line
    end
    res
end

function from_boolean_matrix(input::AbstractSparseMatrix{Bool})
    res = BinAdjacency{Int}()
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
