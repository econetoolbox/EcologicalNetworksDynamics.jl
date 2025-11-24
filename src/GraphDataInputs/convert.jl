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
# (call it "parsing" although input is *julia values*, not strings)
# Input is an(y) iterable of (ref, value) pairs for maps,
# with values elided in the binary case.
# References may be grouped together, as an iterable of references instead.
# For adjacency lists, values are maps themselves,
# and grouping references can also happen with values on the lhs,
# rhs being just a list of "target" references
# (see general module documentation).
#
# Here is how we parse each toplevel input pair: (lhs, rhs).
# Call 'pairs' end the side of this pair that is holding the value(s),
# and 'refs' end the other side, without the value(s).
# Either side is also either grouped or plain:
#           |  refs      |   pairs
#   plain   | ref        |   ref => value
#   grouped | [ref, ref] |  [ref => value, ref => value]
#
# The strategy is to diagnose each side separately,
# attempting to parse as either category,
# asking "forgiveness rather than permission".
# During this diagnosis, normalize any 'plain' input to a (grouped,) input.

# Use this type to hold all temporary status required
# during input parsing, especially useful for quality reporting in case of invalid input.
# This struct is very type-unstable so as to be used for target conversion.
mutable struct Parser
    # Target values types. Nothing for the special binary case.
    T::Option{Type}

    # Useful if known by callers for some reason.
    expected_R::Option{Type}
    # R -> full type of the final adjacency list or map.
    target_type::Function

    # If there is no expected R, infer the expected ref type from the first ref parsed.
    found_first_ref::Bool
    first_ref::Option{Any}

    # Locate currently parsed piece of input like [1, :left, 2, :right]..
    path::Vector{Union{Int,Symbol}}

    # Only fill after checking for consistency, duplications etc.
    result::Union{Nothing,Map,BinMap,Adjacency,BinAdjacency}

    Parser(T, R, target_type) = new(T, R, target_type, false, nothing, [], nothing)

    # Useful to fork into a sub-parser, "asking forgiveness" in case it fails.
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
    a.expected_R = b.expected_R
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

# Keep track of input access path for reporting.
Base.push!(p::Parser, ref) = push!(p.path, ref)
Base.append!(p::Parser, values) = append!(p.path, values)
Base.pop!(p::Parser) = pop!(p.path)
update!(p::Parser, ref) = p.path[end] = ref
bump!(p::Parser) = p.path[end] += 1
path(p::Parser) = "[$(join(p.path, "]["))]"

report(p::Parser) = isempty(p.path) ? "" : " at $(path(p))"
# /!\ possibly long: only include at the end of messages.
function report(p::Parser, input)
    at = report(p)
    "$at: $(repr(input)) ::$(typeof(input))"
end
report(::Nothing, _) = ""

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

# Tag thrown exceptions with a symbol
# to decide which to report in case of multiple 'forgiveness'es.
struct Forgiveness <: Exception
    tag::Symbol
    err::ArgumentError
end
forgerr(tag, mess, raise = throw) = raise(Forgiveness(tag, ArgumentError(mess)))

# Pick the report with highest priority,
# with subtle special-cased tweaks in case of ex-aequo.
# The first given error is found while parsing a plain item, the other a grouped item.
pick(plain::Forgiveness, group::Forgiveness, priorities::Dict{Symbol,Int64}) =
    try
        pp, pg = priorities[plain.tag], priorities[group.tag]
        if pp == pg
            (plain.tag == group.tag == :not_a_ref) && return group # More detailed.
            plain # More user-friendly in general.
        elseif pp < pg
            plain
        else
            group
        end
    catch e
        e isa KeyError || throw("Unexpected pick failure.")
        throw("Either :$(plain.tag) or :$(group.tag) has no priority. \
               This is a bug in the package.")
    end

# Construct report priorities from a sorted vector, highest priority first.
priorities(v::Vector{Symbol}) = Dict(s => i for (i, s) in enumerate(v))

# Upgrade into argument error if bubbling up to user call.
forgive(f, parser) =
    try
        f()
    catch e
        isnothing(parser) && e isa Forgiveness && rethrow(e.err)
        rethrow(e)
    end

#-------------------------------------------------------------------------------------------
# Parsing blocks.

parse_value(p::Parser, input) =
    try
        graphdataconvert(p.T, input)
    catch
        forgerr(
            :not_a_value,
            "Expected values of type '$(p.T)', received instead$(report(p, input)).",
            rethrow,
        )
    end

parse_iterable(p::Parser, input, what) =
    try
        iterate(input)
    catch e
        e isa MethodError && forgerr(
            :not_iterable,
            "Input for $what needs to be iterable.\n\
             Received$(report(p, input)).",
            rethrow,
        )
        rethrow(e)
    end
# Forbid pairs as iterables to alleviate
# https://github.com/econetoolbox/EcologicalNetworksDynamics.jl/issues/182
function parse_iterable(p::Parser, input::Pair, _)
    a, b = input
    forgerr(
        :pair_as_iterable,
        "The pair at $(path(p)) is just considered an iterable in this context, \
         which may be confusing. \
         Consider using an explicit vector instead like [$(repr(a)), $(repr(b))].",
    )
end

parse_pair(p::Parser, input, what) =
    try
        lhs, rhs = input
        # Note that [1, 2, 3] would become (1, 2): raise an error instead.
        try
            _1, _2, _3 = input # That shouldn't work with a true "pair".
            throw(nothing)
        catch e
            isnothing(e) && rethrow("more than 2 values in pair parsing input")
        end
        return lhs, rhs
    catch _
        forgerr(:not_a_pair, "Not a '$what' pair$(report(p, input)).", rethrow)
    end

function parse_plain_ref!(p::Parser, input, what)
    (ref, R, ok) = try
        (graphdataconvert(Symbol, input), Symbol, true)
    catch
        try
            (graphdataconvert(Int, input), Int, true)
        catch
            (nothing, nothing, false)
        end
    end
    ok || forgerr(
        :not_a_ref,
        "Cannot interpret $what reference \
         as integer index or symbol label: \
         received$(report(p, input)).",
    )
    if !isnothing(p.expected_R)
        R == p.expected_R || unexpected_reftype(what, p, input)
    end
    set_if_first!(p, ref)
    fR = typeof(first_ref(p))
    if R != fR
        forgerr(
            :inconsistent_ref_type,
            "$(inferred_ref(what, p)), but $(a_ref(R)) is now found$(report(p, ref)).",
        )
    end
    ref
end
# Reused later.
unexpected_reftype(what, p, input) = forgerr(
    :unexpected_ref_type,
    "Invalid $what reference type. \
     Expected $(repr(p.expected_R)) \
     (or convertible). \
     Received instead$(report(p, input)).",
)
a_ref(R) = "$(R == Symbol ? "a label" : "an index") ($R)"
inferred_ref(what, p) = "The $what reference type for this input \
                         was first inferred to be $(a_ref(typeof(first_ref(p)))) \
                         based on the received '$(repr(first_ref(p)))'"

function parse_plain_pair!(p::Parser, input, refwhat)
    lhs, rhs = parse_pair(p, input, "$refwhat => value")
    push!(p, :left)
    try
        ref = parse_plain_ref!(p, lhs, refwhat)
        update!(p, :right)
        value = parse_value(p, rhs)
        (ref, value)
    catch e
        rethrow(e)
    finally
        pop!(p)
    end
end

# If plain, normalize to grouped.
function parse_grouped_refs!(p::Parser, input, refwhat; ExpectedRefType = nothing)
    (refs, ok) = try
        ref = parse_plain_ref!(p, input, refwhat)
        ((ref,), true)
    catch plain_error
        plain_error isa Forgiveness || rethrow(plain_error) # (not to miss bugs)
        try
            f = fork(p, R -> BinMap{R})
            refs = graphdataconvert(
                BinMap{<:Any},
                input;
                ExpectedRefType,
                parser = f,
                what = (; whole = "group of $(refwhat)s", ref = refwhat),
            )
            merge!(p, f)
            (refs, true)
        catch group_error
            group_error isa Forgiveness || rethrow(group_error)
            (pick(plain_error, group_error, parse_grouped_refs_priorities), false)
        end
    end
    ok || throw(refs)
    refs
end
parse_grouped_refs_priorities = priorities([
    :unexpected_ref_type,
    :inconsistent_ref_type,
    :duplicate_node,
    :duplicate_edge,
    :boolean_label,
    :pair_as_iterable,
    :not_a_ref,
    :not_iterable,
    :no_targets,
    :no_sources,
    :no_values,
    :not_a_value,
    :two_values,
    :not_a_pair,
])

# If plain, normalize to grouped.
function parse_grouped_pairs!(p::Parser, input, refwhat = "node")
    (pairs, ok) = try
        pair = parse_plain_pair!(p, input, refwhat)
        ((pair,), true)
    catch plain_error
        plain_error isa Forgiveness || rethrow(plain_error)
        try
            f = fork(p, R -> Map{R,p.T})
            pairs = graphdataconvert(
                Map{<:Any,p.T},
                input;
                parser = f,
                what = (;
                    whole = "adjacency list",
                    pair = "$refwhat(s) => value(s)",
                    ref = refwhat,
                ),
            )
            merge!(p, f)
            (pairs, true)
        catch group_error
            group_error isa Forgiveness || rethrow(group_error)
            (pick(plain_error, group_error, parse_grouped_pairs_priorities), false)
        end
    end
    ok || throw(pairs)
    pairs
end
parse_grouped_pairs_priorities = priorities([
    :unexpected_ref_type,
    :inconsistent_ref_type,
    :duplicate_node,
    :duplicate_edge,
    :boolean_label,
    :not_a_value,
    :not_a_ref,
    :no_targets,
    :no_sources,
    :no_values,
    :two_values,
    :not_a_pair,
    :pair_as_iterable,
    :not_iterable,
])

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
    forgive(parser) do

        p = isnothing(parser) ? Parser(nothing, ExpectedRefType, R -> BinMap{R}) : parser
        it = parse_iterable(p, input, what.whole)
        isnothing(it) && return empty_result(p)

        push!(p, 0)
        while !isnothing(it)
            bump!(p)
            raw_ref, it = it

            ref = parse_plain_ref!(p, raw_ref, what.ref)
            res = result!(p)
            ref in res && forgerr(
                :duplicate_node,
                "Duplicated $(what.ref) reference$(report(p, raw_ref)).",
            )
            push!(res, ref)

            it = iterate(input, it)
        end

        result!(p)

    end
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
    forgive(parser) do
        # .. although the context is much different:
        # only indices can be retrieved or even *expected* from this kind of input.
        check_boolean_input(
            ExpectedRefType,
            input,
            parser,
            (; whole = what.whole, input = (plur) -> "boolean vector" * ("s"^plur)),
        )
        from_boolean_mask(input)
    end
end

function check_boolean_input(ExpectedRefType, input, parser, what)
    (!isnothing(ExpectedRefType) && ExpectedRefType != Int) && forgerr(
        :boolean_label,
        "A label-indexed $(what.whole) \
         cannot be produced from $(what.input(true))$(report(parser, input)).",
    )
    if !isnothing(parser)
        if isnothing(parser.expected_R)
            parser.expected_R = Int
        end
        if parser.found_first_ref
            parser.first_ref isa Int || forgerr(
                :inconsistent_ref_type,
                "$(inferred_ref(what.whole, parser)), \
                 but a $(what.input(false)) (only yielding indices) \
                 is now found$(report(parser, input)).",
            )
        end
    end
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
    forgive(parser) do

        p = isnothing(parser) ? Parser(T, ExpectedRefType, R -> Map{R,T}) : parser
        it = parse_iterable(p, input, what.whole)
        isnothing(it) && return empty_result(p)

        push!(p, 0)
        while !isnothing(it)
            bump!(p)
            pair, it = it

            refs, raw_value = parse_pair(p, pair, what.pair)
            push!(p, :left) # Start left because :right errors may be much uglier.
            refs = parse_grouped_refs!(p, refs, what.ref; ExpectedRefType)
            update!(p, :right)
            value = parse_value(p, raw_value)
            update!(p, :left)
            res = result!(p)
            push!(p, 0)
            for ref in refs
                bump!(p)
                haskey(res, ref) && forgerr(
                    :duplicate_node,
                    "Duplicated $(what.ref) reference :\n\
                     Received before: $ref => $(res[ref])\n\
                     Received now   : $ref => $(repr(raw_value)) ::$(typeof(raw_value))\
                     $(report(p, ref)).",
                )
                res[ref] = value
            end
            pop!(p)
            pop!(p)

            it = iterate(input, it)
        end

        result!(p)

    end
end

#-------------------------------------------------------------------------------------------
# Parse binary adjacency maps.

function graphdataconvert(
    ::Type{BinAdjacency{<:Any}},
    input;
    ExpectedRefType = nothing,
    parser = nothing,
)
    forgive(parser) do

        p =
            isnothing(parser) ? Parser(nothing, ExpectedRefType, R -> BinAdjacency{R}) :
            parser
        it = parse_iterable(p, input, "binary adjacency map")
        isnothing(it) && return empty_result(p)

        push!(p, 1)
        while !isnothing(it)
            pair, it = it

            raw_sources, raw_targets = parse_pair(p, pair, "source(s) => target(s)")
            push!(p, :left)
            sources = parse_grouped_refs!(p, raw_sources, "source node"; ExpectedRefType)
            update!(p, :right)
            targets = parse_grouped_refs!(p, raw_targets, "target node"; ExpectedRefType)
            res = result!(p)
            update!(p, :left)
            push!(p, 0)
            pend = (length(p.path)-1):length(p.path)
            any_source = false
            any_target = false
            for src in sources
                bump!(p)
                sub = if haskey(res, src)
                    res[src]
                else
                    res[src] = OrderedSet{get_R(p)}()
                end
                safe = p.path[pend]
                p.path[pend] .= (:right, 0)
                for tgt in targets
                    bump!(p)
                    tgt in sub && forgerr(
                        :duplicate_edge,
                        "Duplicate edge specification \
                         $(repr(src)) → $(repr(tgt))$(report(p, tgt)).",
                    )
                    push!(sub, tgt)
                    any_target = true
                end
                pop!(p.path)
                any_target || forgerr(
                    :no_targets,
                    "No target provided for source $(repr(src))$(report(p)).",
                )
                pop!(p.path)
                append!(p, safe)
                any_source = true
            end
            pop!(p)
            any_source || forgerr(:no_sources, "No sources provided$(report(p)).")
            pop!(p)

            it = iterate(input, it)
            bump!(p)
        end

        result!(p)

    end
end

# The binary case *can* accept boolean matrices.
function graphdataconvert(
    ::Type{BinAdjacency{<:Any}},
    input::AbstractMatrix{Bool};
    ExpectedRefType = nothing,
    parser = nothing,
    what = (; whole = "binary adjacency list"),
)
    forgive(parser) do
        check_boolean_input(
            ExpectedRefType,
            input,
            parser,
            (;
                whole = what.whole,
                input = (plur) -> "boolean matri" * (plur ? "ces" : "x"),
            ),
        )
        from_boolean_matrix(input)
    end
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
# Parse adjacency maps.

function graphdataconvert(
    ::Type{Adjacency{<:Any,T}},
    input;
    ExpectedRefType = nothing,
    parser = nothing,
) where {T}
    forgive(parser) do

        p = isnothing(parser) ? Parser(T, ExpectedRefType, R -> Adjacency{R,T}) : parser
        it = parse_iterable(p, input, "adjacency map")
        isnothing(it) && return empty_result(p)

        push!(p, 0)
        while !isnothing(it)
            bump!(p)
            pair, it = it

            lhs, rhs = parse_pair(p, pair, "source(s) => target(s)")
            (lhs, lhs_has_values), (rhs, rhs_has_values) = map((
                (lhs, :left, "source"),
                (rhs, :right, "target"),
            )) do (side, step, refwhat)
                push!(p, step)
                (group, has_values, ok) = try
                    (parse_grouped_pairs!(p, side, refwhat), true, true)
                catch e_pairs
                    e_pairs isa Forgiveness || rethrow(e_pairs)
                    try
                        (parse_grouped_refs!(p, side, refwhat; ExpectedRefType), false, true)
                    catch e_refs
                        e_refs isa Forgiveness || rethrow(e_refs)
                        (pick(e_pairs, e_refs, adjacency_map_priorities), nothing, false)
                    end
                end
                ok || throw(group)
                pop!(p)
                (group, has_values)
            end

            (lhs_has_values && rhs_has_values) && forgerr(
                :two_values,
                "Cannot associate values to both source and target ends \
                 of edges at $(path(p)):\n\
                 Received LHS: $lhs\n\
                 Received RHS: $rhs.",
            )
            !(lhs_has_values || rhs_has_values) && forgerr(
                :no_value,
                "No values found for either source or target end of edges at $(path(p)):\n\
                 Received LHS: $lhs\n\
                 Received RHS: $rhs.",
            )

            res = result!(p)

            push!(p, :left)
            push!(p, 0)
            pend = (length(p.path)-1):length(p.path)
            any = false
            for i in lhs # Values are either collected here..
                bump!(p)
                any = true
                (src, value) = lhs_has_values ? i : (i, missing)
                sub = if haskey(res, src)
                    res[src]
                else
                    res[src] = OrderedDict{get_R(p),T}()
                end
                safe = p.path[pend]
                p.path[pend] .= (:right, 0)
                for j in rhs # .. or there.
                    bump!(p)
                    (tgt, value) = rhs_has_values ? j : (j, value)
                    haskey(sub, tgt) && forgerr(
                        :duplicate_edge,
                        "Duplicate edge specification:\n\
                         Previously received: \
                         $(repr(src)) → $(repr(tgt)) ($(sub[tgt]))\n\
                         Now received:        \
                         $(repr(src)) → $(repr(tgt)) ($value)\
                         $(report(p, tgt)).",
                    )
                    sub[tgt] = value
                end
                p.path[pend] .= safe
                if isempty(sub)
                    e = lhs_has_values ? "source" : "target"
                    forgerr(
                        :no_targets,
                        "No target provided for `$e => value` pair$(report(p)).",
                    )
                end
            end
            any || forgerr(:no_sources, "No sources provided$(report(p)).")
            pop!(p)
            pop!(p)

            it = iterate(input, it)
        end

        result!(p)

    end
end
adjacency_map_priorities = priorities([
    :unexpected_ref_type,
    :inconsistent_ref_type,
    :duplicate_node,
    :duplicate_edge,
    :boolean_label,
    :not_a_value,
    :not_a_ref,
    :not_a_pair,
    :no_targets,
    :no_sources,
    :no_values,
    :two_values,
    :pair_as_iterable,
    :not_iterable,
])

#-------------------------------------------------------------------------------------------
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
    targets = parse_types(types, Target, loc)
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
