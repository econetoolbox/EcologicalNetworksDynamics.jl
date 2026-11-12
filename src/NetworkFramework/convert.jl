# Typical default converters from input data:
#
# - (*) `Real -> Float64` (in particular: `Integer -> Float64`)
# - (*) `Integer` -> Bool` (let julia guard against values other than `0` or `1`)
# - (*) `Integer` -> Int64`
# - `(Symbol, Char) -> String`
# - `(AbstractString, Char) -> Symbol`
#
# Conversions marked with (*) are also implicitly performed on collections types
# for positive graph levels (nodes & edges):
# For `Coll` in `{Vector, Matrix, SparseVector, SparseMatrix}`:
#
# - `Coll{<:Real} -> Coll{Float64}`
# - `Coll{<:Integer} -> Coll{Bool}`
# - `Coll{<:Integer} -> Coll{Int64}`
#
# Additionally:
#
# - `Vector{*} -> SparseVector{*}`
# - `Matrix{*} -> SparseMatrix{*}`

# ==========================================================================================
# Scalar conversions.

"Get a static response whether the type *may* be converted."
can_convert(::Type, ::Type) = false # Unless explicitly marked.
can_convert(T::Type, x) = can_convert(T, typeof(x))

function allow_convert(Target, Input, f = Target)
    eval(
        quote
            convert(::Type{$Target}, v::$Input) =
                try
                    $f(v)
                catch e
                    e isa LibError && rethrow(e)
                    converr($Target, v, "(detail down the stacktrace)")
                end
            can_convert(::Type{$Target}, ::Type{<:$Input}) = true
        end,
    )
end
ac = allow_convert

# If the type is already correct, then an alias should be returned.
can_convert(::Type{T}, ::T) where T = true
convert(::Type{T}, x::T) where T = x

# ==========================================================================================
# Accepted implicit scalar conversions.

ac(String, Symbol)
ac(String, Char, c -> "$c")
ac(Symbol, Char)
ac(Symbol, AbstractString)
ac(Bool, Integer)
ac(Int, Integer)
ac(Float64, Real)

# ==========================================================================================
# Convert to dense arrays.

# From iterators.
has_iter(T::Type) = hasmethod(iterate, Tuple{T}) # Useful for arbitrary iterators.
has_pairs(T::Type) = hasmethod(pairs, Tuple{IndexCartesian,T}) # Useful for n-D arrays.
# The above is not actually called, but excludes e.g. `pair(Type)`.
# https://julialang.zulipchat.com/#narrow/channel/274208-helpdesk-.28published.29/topic/pairs.28Type.29/with/639765958

check_pairs(A, x) =
    has_pairs(typeof(x)) || converr(A, x, "Input is not iterable as an array.")
check_iter(A, x) = has_iter(typeof(x)) || converr(A, x, "Input is not iterable.")

can_convert(::Type{<:AbstractArray}, x) = has_pairs(typeof(x))
check_convert(A::Type{<:AbstractArray}, x) = check_pairs(A, x)
function convert(A::Type{<:AbstractArray}, input)
    check_convert(A, input)
    T = eltype(A)
    T[
        try
            convert(T, x)
        catch e
            e isa ConvertError || rethrow(e)
            e.ref = UserRef(Tuple(i))
            rethrow(e)
        end
        for (i, x) in getpairs(input)
    ]
end
getpairs(x) = enumerate(x) # For arbitrary iterators.
getpairs(x::AbstractArray) = pairs(x) # For arrays.

# Vectors could be built from any kind of iterator.
can_convert(::Type{<:AbstractVector}, x) = has_iter(typeof(x))
check_convert(A::Type{<:AbstractVector}, x) = check_iter(A, x)

convert(::Type{A}, a::A) where A<:AbstractArray = a

#-------------------------------------------------------------------------------------------
# Reject a few unfortunate consequences.

# Key-based structures.
can_convert(::Type{<:AbstractArray}, ::AbstractDict) = false
can_convert(::Type{<:AbstractArray}, ::NamedTuple) = false
check_convert(A::Type{<:AbstractArray}, x::AbstractDict) = keyerr(A, x, AbstractDict)
check_convert(A::Type{<:AbstractArray}, x::NamedTuple) = keyerr(A, x, NamedTuple)
keyerr(A, x, T) = converr(A, x, "Would not convert $T to an array: keys would be lost.")

# Uneven number of dimensions.
can_convert(A::Type{<:AbstractArray}, a::AbstractArray) = ndims(A) == ndims(a)
check_convert(A::Type{<:AbstractArray}, a::AbstractArray) =
    can_convert(A, a) || converr(A, a,
        "Would not convert vector to matrix, vice-versa or etc.")

# Rewire the above vector special-case :\
for X in (AbstractDict, NamedTuple, AbstractArray)
    eval(
        quote
            can_convert(A::Type{<:AbstractVector}, x::$X) =
                @invoke can_convert(A::Type{<:AbstractArray}, x)
            check_convert(A::Type{<:AbstractVector}, x::$X) =
                @invoke check_convert(A::Type{<:AbstractArray}, x)
        end,
    )
end

# ==========================================================================================
# Convert to sparse arrays.

has_zero(T::Type) = hasmethod(zero, Tuple{T})
has_size(T::Type) = hasmethod(size, Tuple{T})

function check_zero(A::Type{<:AbstractArray}, x)
    T = eltype(A)
    has_zero(T) || converr(A, x,
        "Would not convert to a sparse structure \
         when the element type ($yellow$T$reset) has no null/zero value.")
end

function check_size(A, x)
    has_size(typeof(x)) || converr(A, x,
        "Would not convert to a sparse structure when the input has no `size`.")
end

can_convert(A::Type{<:AbstractSparseArray}, x) = has_zero(eltype(A)) && has_size(typeof(x))
function sparse_check_convert(A::Type{<:AbstractSparseArray}, x)
    check_zero(A, x)
    check_size(A, x)
    check_convert(A, x)
end

function convert(A::Type{<:AbstractSparseArray}, input)
    sparse_check_convert(A, input)
    T = eltype(A)
    res = spzeros(T, size(input))
    for (i, x) in pairs(input)
        has_zero(typeof(x)) ||
            converr(A, x, "Element cannot be compared to null/zero.";
                ref = UserRef(Tuple(i)))
        iszero(x) && continue
        res[i] = try
            convert(T, x)
        catch e
            e isa ConvertError || rethrow(e)
            e.ref = UserRef(Tuple(i))
            rethrow(e)
        end
    end
    res
end
convert(::Type{A}, a::A) where A<:AbstractSparseArray = a

can_convert(A::Type{<:AbstractSparseArray}, a::AbstractArray) =
    has_zero(eltype(A)) && @invoke can_convert(A::Type{<:AbstractArray}, a)

function sparse_check_convert(A::Type{<:AbstractSparseArray}, a::AbstractArray)
    check_zero(A, a)
    check_convert(A::Type{<:AbstractArray}, a)
end

# ==========================================================================================
"""
Try successive conversions until one succeeds,
applying the corresponding function to the result prior to returning it then.

`tries` are:

```
[
  T,      # Sugar for (Type, identity).
  (T, f), # (Type, transform(converted_result) -> returned_result)
  ...
]
```
"""
function try_convert(input, tries...)
    attempts = FailedAttempts()
    for t in tries
        (T, then) = try
            a, b = t
            a, b
        catch _
            (t, identity)
        end
        x = try
            convert(T, input)
        catch e
            e isa LibError || rethrow(e)
            push!(attempts, "convert input to $T")
            continue
        end
        return then(x)
    end
    mess = IOBuffer()
    print(mess, "Cannot convert input to either:")
    for t in tries
        (T, _) = try
            a, b = t
            a, b
        catch _
            (t, identity)
        end
        print(mess, "\n  - $T")
    end
    print(mess, "\n(see attempts down the stacktrace)")
    mess = String(Base.take!(mess))
    # Raise *both* exceptions for full info.
    try
        throw(attempts)
    catch _
        checkerr(input, mess)
    end
end

"""
Execute one or the other block named by end user.
`tries` are:

```
[
  (Symbol, Function() -> returned_result)
]
```
"""
function from_name(input, tries...; kw...)
    name = convert(Symbol, input)
    expected = Symbol[]
    for (attempt, fn) in tries
        name == attempt && return fn()
        push!(expected, attempt)
    end
    exp = join_elided(expected, ", ", " or "; coleach = green)
    checkerr(input, "Expected one of [$exp]."; kw...)
end

# ==========================================================================================

"Report input problem during conversion, to be possibly later upgraded into `CheckError`."
mutable struct ConvertError <: LibError
    Target::Type
    value::Any
    ref::InputRef
    mess::String
end
converr(T::Type, value, mess::String, throw = Base.throw; ref = UserRef(wholedata)) =
    throw(ConvertError(T, value, ref, mess))

function CheckError(e::ConvertError)
    (; Target, value, ref, mess) = e
    # TODO: not exactly satisfied with this upgrade,
    # but nesting exception types complicates things much more?
    mess = "Cannot convert to `$Target`:\n" * mess
    CheckError(value, mess; uref = ref.ref) # (weird uref round-twist :\)
end

function Base.showerror(io::IO, e::ConvertError)
    # Impl *should* be standalone, but reuse CheckError code for now just because it works.
    e = CheckError(e)
    showerror(io, e)
end
