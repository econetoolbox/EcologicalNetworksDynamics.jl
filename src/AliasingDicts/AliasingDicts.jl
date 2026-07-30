"""
Design a data structure behaving like a julia's Dict{Symbol, T},
but alternate references can be given as a key, aka key aliases.
Constructing the type requires providing aliases specifications,
under the form of an 'AliasingSystem'.
Terminology:

  - "reference": anything given by user to access data in the structure.
  - "standard": the actual key used to store the data
  - "alias": non-standard reference possibly used to access the data.
    The type should protect from ambiguous aliasing specifications.
"""
module AliasingDicts

import EcologicalNetworksDynamics: Option, methlhs, argerr

using OrderedCollections
using StringCases

"""
The aliased type takes care of bookeeping aliases, references and standards.
Subtypes can be created with `define_aliasing_dict()`DR
"""
abstract type AliasingDict{T} <: AbstractDict{Symbol,T} end
const AD = AliasingDict

#-------------------------------------------------------------------------------------------
# Base interface.
# Don't leak mutable data/references which be (mis)used to corrupt the aliasing system.

#  (standard ↦ (ref, ref, ref..)) with refs sorted by length then lexicographic.
#  (repeat the standard among aliases within references so that it is also ordered with them)
references(D::Type{<:AD}) = throw("Unimplemented references for $D.")
# (reference ↦ standard)
revmap(D::Type{<:AD}) = throw("Unimplemented revmap for $D.")
# The kind of things we are referring to.
# (useful for error messages and code generation)
name(D::Type{<:AD}) = throw("Unimplemented name for $D.")
shortname(D::Type{<:AD}) = throw("Unimplemented shortname for $D.")

#-------------------------------------------------------------------------------------------
# Default interface constructed upon the above.

Base.length(D::Type{<:AD}) = Base.length(references(D))
standards(D::Type{<:AD}) = keys(references(D))

function standardize(ref, D::Type{<:AD})
    key = Symbol(ref)
    r = revmap(D)
    if key in keys(r)
        r[key]
    else
        throw(AliasingError(name(D), "Invalid reference: '$ref'."))
    end
end

# Get all alternate references.
references(ref, D::Type{<:AD}) = references(D)[standardize(ref, D)]
all_references(D::Type{<:AD}) = (r for refs in references(D) for r in refs)

# Construct cheat-sheet with all standards, their order and aliases.
aliases(D::Type{<:AD}) =
    OrderedDict(s => [r for r in references(s, D) if r != s] for s in standards(D))

# Get first alias (shortest + earliest lexically).
shortest(ref, D::Type{<:AD}) = first(references(ref, D))

# Match reference to others, regardless of aliasing.
is(ref_a, ref_b, D::Type{<:AD}) = standardize(ref_a, D) == standardize(ref_b, D)
isin(ref, refs, D::Type{<:AD}) = any(standardize(ref, D) == standardize(r, D) for r in refs)
isref(key, D::Type{<:AD}) = any(Symbol(key) in refs for refs in references(D))

#-------------------------------------------------------------------------------------------
# Defer basic instances interface to the interface of dict,
# assuming all subtypes are of the form:
#  struct Sub{T} <: AD{T}
#      _d::Dict{Symbol,T}
#  end

# Basic methods(dict).
for fn in (length, iterate)
    FN = typeof(fn)
    eval(quote
        (::$FN)(d::AD) = $fn(d._d)
    end)
end
# Basic methods(dict, key).
for fn in (haskey, getindex, get, pop!)
    FN = typeof(fn)
    eval(quote
        (::$FN)(d::D, k) where {D<:AD} = $fn(d._d, standardize(k, D))
    end)
end
# Basic methods(dict, key, third_arg).
for fn in (get, get!, pop!)
    FN = typeof(fn)
    eval(quote
        (::$FN)(d::D, k, x) where {D<:AD} = $fn(d._d, standardize(k, D), x)
    end)
end
# Less basic methods.
Base.setindex!(d::D, v, k) where {D<:AD} = setindex!(d._d, v, standardize(k, D))
Base.merge(d::AD, b::AD) = AliasingDict(merge(d._d, b._d))
Base.iterate(d::AD, state) = iterate(d._d, state)
Base.:(==)(d::AD, b::AD) = d._d == b._d

# Extend all type-related methods to corresponding instances.
# Basic methods(D).
for fn in (shortname, name, standards, references, aliases)
    FN = typeof(fn)
    eval(quote
        (::$FN)(::D) where {D<:AD} = $fn(D)
    end)
end
# Basic methods(ref, D).
for fn in (references, standardize, shortest, isref)
    FN = typeof(fn)
    eval(quote
        (::$FN)(ref, ::D) where {D<:AD} = $fn(ref, D)
    end)
end
# Less basic methods(first_arg, second_arg, D).
for fn in (is, isin)
    FN = typeof(fn)
    eval(quote
        (::$FN)(x, y, ::D) where {D<:AD} = $fn(x, y, D)
    end)
end

#-------------------------------------------------------------------------------------------
"""
Generate a correct AliasingDict concrete subtype.

Note: Implemented using named tuples,
so don't overuse entries and aliases,
or we could get performance issues above 32/64 entries?
"""
function define_aliasing_dict(
    mod::Module,
    DictName::Symbol,
    system_name::String,
    shortname::Symbol,
    raw_refs,
)

    # Construct references and surjections.
    references = OrderedDict()
    revmap = OrderedDict()
    err(mess) = throw(AliasingError(system_name, mess))
    for (i, pair) in enumerate(raw_refs)
        std, refs = try
            a, b = pair
            (a, b)
        catch
            argerr("Not a pair of `standard => [references..]` at [$i]: $(repr(pair)).")
        end
        std isa Symbol || argerr("Not a symbol at [$i]: $(repr(std)).")
        aliases = map(enumerate(refs)) do (j, al)
            al isa Symbol ||
                argerr("Not a symbol alias (at [$j]) for $(repr(std)): $(repr(al))")
            al
        end
        refs = vcat([Symbol(a) for a in aliases], [std])
        references[std] = sort!(sort!(refs); by = x -> length(string(x)))
        for ref in refs
            # Protect from ambiguity.
            if ref in keys(revmap)
                target = revmap[ref]
                if target == std
                    err("Duplicated $system_name alias for '$std': '$ref'.")
                end
                err(
                    "Ambiguous $system_name reference: " *
                    "'$ref' either means '$target' or '$std'.",
                )
            end
            revmap[ref] = std
        end
    end

    # Type generation happens in the caller's chosen module.
    xp = quote
        struct $DictName{T} <: $AD{T}
            _d::$Dict{$Symbol,T}
            $DictName{T}(::$Type{$InnerConstruct}, pairs) where {T} =
                new{T}($construct(pairs, $DictName, T))
        end
        $DictName
    end
    DictType = mod.eval(xp)

    # Additional methods generation happen within this module.

    # Generate tuple expressions to implement base methods.
    refs = NamedTuple(std => Tuple(refs) for (std, refs) in references)
    revs = NamedTuple(revmap)

    DT = DictType
    MD = methlhs(DictType)
    AliasingDicts.eval(
        quote

            # Base methods.
            references(::Type{<:$DT}) = $refs
            revmap(::Type{<:$DT}) = $revs
            name(::Type{<:$DT}) = $system_name
            shortname(::Type{<:$DT}) = $(Meta.quot(shortname))

            # Infer common type from pairs, and automatically convert keys to symbols.
            function $MD(args::Pair...)
                g = ((Symbol(k), v) for (k, v) in args)
                $DT{common_type_for(g)}(InnerConstruct, g)
            end

            # Same with keyword arguments as keys, default to Any for empty dict.
            $MD(; kwargs...) =
                if isempty(kwargs)
                    $DT{Any}(InnerConstruct, ())
                else
                    T = common_type_for(kwargs)
                    $DT{T}(InnerConstruct, kwargs)
                end

            # Automatically convert keys to symbols, and values to the given T.
            $MD{T}(args...) where {T} =
                $DT{T}(InnerConstruct, ((Symbol(k), v) for (k, v) in args))

            # Same with keyword arguments as keys.
            $MD{T}(; kwargs...) where {T} = $DT{T}(InnerConstruct, kwargs)
        end,
    )
    DictType
end
export define_aliasing_dict

# Marker dispatching to the underlying constructor.
struct InnerConstruct end

# Construct from (key ↦ value) iterable with explicit type.
function construct(pairs, DictType::Type{<:AliasingDict}, T::Type)
    d = Dict{Symbol,T}()
    # Guard against redundant/ambiguous specifications.
    norm = Dict{Symbol,Symbol}() #  standard => ref
    for (ref, value) in pairs
        standard = standardize(ref, DictType)
        if standard in keys(norm)
            aname = titlecase(name(DictType))
            throw(
                AliasingError(
                    name(DictType),
                    "$aname type '$standard' specified twice: " *
                    "once with '$(norm[standard])' " *
                    "and once with '$ref'.",
                ),
            )
        end
        norm[standard] = ref
        d[standard] = value
    end
    d
end

# Extract the less abstract common type from the given keyword arguments.
function common_type_for(pairs_generator)
    GItem = Base.@default_eltype(pairs_generator) # .. provided I am allowed to use this?
    GItem.parameters[2]
end

# Dedicated exception type.
struct AliasingError <: Exception
    name::String
    message::String
end
function Base.showerror(io::IO, e::AliasingError)
    print(io, "In aliasing system for $(repr(e.name)): $(e.message)")
end
export AliasingError

# Useful APIs can be crafted out of nesting two aliased dicts together.
include("./nested_2D_api.jl")

# ==========================================================================================
# Display.

# Compact display with only short references.
function display_short(d::AD)
    D = typeof(d)
    "($(join(("$(shortest(k, D)): $v" for (k, v) in d), ", ")))"
end

# Full display with aliases.
# Optionally indent by increasing level.
function display_long(d::AD; level = 0)
    isempty(d) && return "()"
    ind(n) = "\n" * repeat("  ", level + n)
    res = "("
    for (ref, aliases) in aliases(d)
        haskey(d, ref) || continue
        res *= ind(1) * "$ref ($(join(repr.(aliases), ", "))) => $(d[ref]),"
    end
    res * ind(0) * ")"
end

function Base.show(io::IO, d::AD{T}) where {T}
    D = typeof(d)
    print(io, "$D$(display_short(d))")
end

function Base.show(io::IO, ::MIME"text/plain", d::AD{T}) where {T}
    D = typeof(d)
    print(io, "$D$(display_long(d))")
end

end
