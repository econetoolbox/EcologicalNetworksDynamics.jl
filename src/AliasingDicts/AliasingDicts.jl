module AliasingDicts

using OrderedCollections
using StringCases
using MacroTools
import ..Option

# Design a data structure behaving like a julia's Dict{Symbol, T},
# but alternate references can be given as a key, aka key aliases.
# Constructing the type requires providing aliases specifications,
# under the form of an 'AliasingSystem'.
# Terminology:
#   - "reference": anything given by user to access data in the structure.
#   - "standard": the actual key used to store the data
#   - "alias": non-standard reference possibly used to access the data.
# The type should protect from ambiguous aliasing specifications.

# ==========================================================================================
# The aliased type takes care
# of bookeeping aliases, references and standards.
# Subtypes can be created with the dedicated macro.

abstract type AliasingDict{T} <: AbstractDict{Symbol,T} end

#-------------------------------------------------------------------------------------------
# Base queries that subtypes should answer.
# Note: only return immutable data/references for them,
# or the aliasing system could become corrupted.

# (standard ↦ (ref, ref, ref..)) with refs sorted by length then lexicog, including.
# (repeat the standard among aliases within references so that it is also ordered with them)
references(D::Type{<:AliasingDict}) = throw("Unimplemented references for $D.")
# (reference ↦ standard)
revmap(D::Type{<:AliasingDict}) = throw("Unimplemented revmap for $D.")
# What kind of things are we referring to?
# (useful for error messages and code generation)
name(D::Type{<:AliasingDict}) = throw("Unimplemented name for $D.")
shortname(D::Type{<:AliasingDict}) = throw("Unimplemented shortname for $D.")

#-------------------------------------------------------------------------------------------
# Construct upon the above aliasing system "trait".

Base.length(D::Type{<:AliasingDict}) = Base.length(references(D))
standards(D::Type{<:AliasingDict}) = keys(references(D))

function standardize(ref, D::Type{<:AliasingDict})
    key = Symbol(ref)
    r = revmap(D)
    if key in keys(r)
        r[key]
    else
        throw(AliasingError(name(D), "Invalid reference: '$ref'."))
    end
end

# Get all alternate references.
references(ref, D::Type{<:AliasingDict}) = references(D)[standardize(ref, D)]
all_references(D::Type{<:AliasingDict}) = (r for refs in references(D) for r in refs)

# Construct cheat-sheet with all standards, their order and aliases.
aliases(D::Type{<:AliasingDict}) =
    OrderedDict(s => [r for r in references(s, D) if r != s] for s in standards(D))

# Get first alias (shortest + earliest lexically).
shortest(ref, D::Type{<:AliasingDict}) = first(references(ref, D))

# Match reference to others, regardless of aliasing.
is(ref_a, ref_b, D::Type{<:AliasingDict}) = standardize(ref_a, D) == standardize(ref_b, D)
isin(ref, refs, D::Type{<:AliasingDict}) =
    any(standardize(ref, D) == standardize(r, D) for r in refs)
isref(key, D::Type{<:AliasingDict}) = any(Symbol(key) in refs for refs in references(D))

#-------------------------------------------------------------------------------------------
# Defer basic instances interface to the interface of dict,
# assuming all subtypes are of the form:
#  struct Sub{T} <: AliasingDict{T}
#      _d::Dict{Symbol,T}
#  end

# Basic methods(dict).
for fn in (:length, :iterate)
    eval(quote
        Base.$fn(d::AliasingDict) = Base.$fn(d._d)
    end)
end
# Basic methods(dict, key).
for fn in (:haskey, :getindex, :get, :pop!)
    eval(quote
        Base.$fn(d::D, k) where {D<:AliasingDict} = Base.$fn(d._d, standardize(k, D))
    end)
end
# Basic methods(dict, key, third_arg).
for fn in (:get, :get!, :pop!)
    eval(
        quote
            Base.$fn(d::D, k, x) where {D<:AliasingDict} =
                Base.$fn(d._d, standardize(k, D), x)
        end,
    )
end
# Less basic methods.
Base.setindex!(d::D, v, k) where {D<:AliasingDict} =
    Base.setindex!(d._d, v, standardize(k, D))
Base.merge(d::AliasingDict, b::AliasingDict) = AliasingDict(merge(d._d, b._d))
Base.iterate(d::AliasingDict, state) = Base.iterate(d._d, state)
Base.:(==)(d::AliasingDict, b::AliasingDict) = d._d == b._d

# Extend all type-related methods to corresponding instances.
# Basic methods(D).
for fn in (:shortname, :name, :standards, :references, :aliases)
    eval(quote
        $fn(::D) where {D<:AliasingDict} = $fn(D)
    end)
end
# Basic methods(ref, D).
for fn in (:references, :standardize, :shortest, :isref)
    eval(quote
        $fn(ref, ::D) where {D<:AliasingDict} = $fn(ref, D)
    end)
end
# Less basic methods(first_arg, second_arg, D).
for fn in (:is, :isin)
    eval(quote
        $fn(x, y, ::D) where {D<:AliasingDict} = $fn(x, y, D)
    end)
end

#-------------------------------------------------------------------------------------------
# Generate a correct AliasingDict concrete subtype.

# Note: Implemented using named tuples,
# so don't overuse entries and aliases,
# or we could get performance issues above 32/64 entries?

:((a => [:ref], b => [:ref])).args[1].args
macro aliasing_dict(DictName, system_name, shortname, raw_refs)
    argerr(mess) = throw(ArgumentError(mess))
    is_symbol(xp) = xp isa Symbol
    is_sequence(xp) = xp isa Expr && xp.head in (:vect, :tuple)
    unwrap_quotenode(xp) =
        if xp isa QuoteNode
            xp.value
        else
            argerr("Not a QuoteNode: $(repr(xp)).")
        end

    is_symbol(DictName) ||
        argerr("Not a symbol name for an aliasing dict type: $(repr(DictName)).")

    shortname = unwrap_quotenode(shortname)
    is_symbol(shortname) ||
        argerr("Not a symbol short name for '$DictName' dict type: $(repr(shortname))")

    system_name isa String ||
        argerr("Not a string name for an aliasing dict type: $(repr(system_name)).")

    is_sequence(raw_refs) || argerr("Not a vect or tuple of references: $(repr(raw_refs)).")

    # Construct references and surjections.
    references = OrderedDict()
    revmap = OrderedDict()
    err(mess) = throw(AliasingError(system_name, mess))
    for arg in raw_refs.args
        (false) && (local std, refs) # (reassure JuliaLS)
        @capture(arg, std_ => refs_)
        isnothing(std) &&
            argerr("Not a pair of `standard => [references..]`: $(repr(arg)).")
        std = unwrap_quotenode(std)
        is_symbol(std) || argerr("Not a symbol: $(repr(std)).")
        is_sequence(refs) ||
            argerr("Not a vect or tuple of aliases for $(repr(std)): $(repr(refs)).")
        aliases = map(refs.args) do al
            al = unwrap_quotenode(al)
            is_symbol(al) || argerr("Not a symbol alias for $(repr(std)): $(repr(al))")
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

    # Generate tuple expressions to implement base methods.
    refs_xp = :(())
    refs_xp.args =
        [:($std = $(Expr(:tuple, Meta.quot.(refs)...))) for (std, refs) in references]

    rev_xp = :(())
    rev_xp.args = [:($rev = $(Meta.quot(std))) for (rev, std) in revmap]

    # Type generation.
    DictName = esc(DictName)
    quote

        struct $DictName{T} <: AliasingDict{T}
            _d::Dict{Symbol,T}

            # Construct from (key ↦ value) generator with explicit type.
            function $DictName{T}(::Type{InnerConstruct}, generator) where {T}
                d = Dict{Symbol,T}()
                # Guard against redundant/ambiguous specifications.
                norm = Dict{Symbol,Symbol}() #  standard => ref
                for (ref, value) in generator
                    standard = standardize(ref, $DictName)
                    if standard in keys(norm)
                        aname = titlecase(name($DictName))
                        throw(
                            AliasingError(
                                $system_name,
                                "$aname type '$standard' specified twice: " *
                                "once with '$(norm[standard])' " *
                                "and once with '$ref'.",
                            ),
                        )
                    end
                    norm[standard] = ref
                    d[standard] = value
                end
                new{T}(d)
            end
        end

        # Base methods.
        AliasingDicts.references(::Type{<:$DictName}) = $refs_xp
        AliasingDicts.revmap(::Type{<:$DictName}) = $rev_xp
        AliasingDicts.name(::Type{<:$DictName}) = $system_name
        AliasingDicts.shortname(::Type{<:$DictName}) = $(Meta.quot(shortname))

        # Infer common type from pairs, and automatically convert keys to symbols.
        function $DictName(args::Pair...)
            g = ((Symbol(k), v) for (k, v) in args)
            $DictName{common_type_for(g)}(InnerConstruct, g)
        end

        # Same with keyword arguments as keys, default to Any for empty dict.
        $DictName(; kwargs...) =
            if isempty(kwargs)
                $DictName{Any}(InnerConstruct, ())
            else
                $DictName{common_type_for(kwargs)}(InnerConstruct, kwargs)
            end

        # Automatically convert keys to symbols, and values to the given T.
        $DictName{T}(args...) where {T} =
            $DictName{T}(InnerConstruct, ((Symbol(k), v) for (k, v) in args))

        # Same with keyword arguments as keys.
        $DictName{T}(; kwargs...) where {T} = $DictName{T}(InnerConstruct, kwargs)

    end
end
export @aliasing_dict

# Marker dispatching to the underlying constructor.
struct InnerConstruct end

# Extract the less abstract common type from the given keyword arguments.
function common_type_for(pairs_generator)
    GItem = Base.@default_eltype(pairs_generator) # .. provided I am allowed to use this?
    T = GItem.parameters[2]
    return T
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
function display_short(d::AliasingDict)
    D = typeof(d)
    "($(join(("$(shortest(k, D)): $v" for (k, v) in d), ", ")))"
end

# Full display with aliases.
# Optionally indent by increasing level.
function display_long(d::AliasingDict; level = 0)
    isempty(d) && return "()"
    ind(n) = "\n" * repeat("  ", level + n)
    res = "("
    for (ref, aliases) in aliases(d)
        haskey(d, ref) || continue
        res *= ind(1) * "$ref ($(join(repr.(aliases), ", "))) => $(d[ref]),"
    end
    res * ind(0) * ")"
end

function Base.show(io::IO, d::AliasingDict{T}) where {T}
    D = typeof(d)
    print(io, "$D$(display_short(d))")
end

function Base.show(io::IO, ::MIME"text/plain", d::AliasingDict{T}) where {T}
    D = typeof(d)
    print(io, "$D$(display_long(d))")
end

end
