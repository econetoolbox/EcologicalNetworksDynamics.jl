# Flexibility is allowed on the input type,
# with the following conversions implicitly performed:

# - (*) `Real -> Float64` (in particular: `Integer -> Float64`)
# - (*) `Integer` -> Bool` (let julia guard against values other than `0` or `1`)
# - (*) `Integer` -> Int64`
# - `(Symbol, Char) -> String`
# - `(AbstractString, Char) -> Symbol`

# Conversions marked with (*) are also implicitly performed on collections types.
# For `Coll` in `{Vector, Matrix, SparseVector, SparseMatrix}`:

# - `Coll{<:Real} -> Coll{Float64}`
# - `Coll{<:Integer} -> Coll{Bool}`
# - `Coll{<:Integer} -> Coll{Int64}`

# Additionally:

# - `Vector{*} -> SparseVector{*}`
# - `Matrix{*} -> SparseMatrix{*}`

# No other conversion is implicitly performed yet.

# Matching julia's `convert` behaviour,
# if there is no need to construct or convert to a new value,
# then the original value is used, and so the user keeps an *aliased reference* to it.
# This makes it possible for user to avoid unnecessary copies
# at the cost of providing the exact correct type.

"""
Without any context, call with a target type to convert input.
"""
inputconvert(T, input) = inerr("Cannot convert from $(typeof(input)) to $T.")
inputconvert(::Type{T}, input::T) where {T} = input

# ==========================================================================================
# Scalar conversions.
function allow_convert(Target, Input, f)
    eval(
        quote
            inputconvert(::Type{$Target}, v::$Input) =
                try
                    $f(v)
                catch e
                    e isa InputError && rethrow(e)
                    inerr("Error when attempting to convert input \
                           (detail down the stacktrace):\n\
                           Target type was $($Target).\n\
                           Input was: $(repr(v)) ::$(typeof(v))")
                end
        end,
    )
end
ac = allow_convert

# ==========================================================================================
# Simple collections conversions.

to_dense(f) = array -> [f(e) for e in array]
function ac_dense(Target, pairs...) # (Input, convert_function)...
    for (Input, f) in pairs
        ac(Target, Input, f)
        ac(Vector{Target}, Vector{<:Input}, to_dense(f))
        ac(Matrix{Target}, Matrix{<:Input}, to_dense(f))
    end

    # Don't shadow the identity case, which should return an alias of the input.
    ac(Target, Target, identity)
    ac(Vector{Target}, Vector{Target}, identity)
    ac(Matrix{Target}, Matrix{Target}, identity)
end

# Textual values have no julia `zero` and don't make sense in sparse structures.
ac_dense(String, (Symbol, String), (Char, c -> "$c"))
ac_dense(Symbol, (AbstractString, Symbol), (Char, Symbol))

# No custom conversion function for sparse arrays
# because it does not necessarily translate in term of julia's `iszero`,
# required for sparse structures.
to_sparse(Target, Input) = array -> begin
    res = spzeros(Input, size(array))
    for (i, e) in enumerate(array)
        iszero(e) && continue
        res[i] = Target(e)
    end
    res
end
function ac_sparse(Target, Input)
    ac(SparseVector{Target}, SparseVector{<:Input}, SparseVector{Target})
    ac(SparseMatrix{<:Input}, SparseMatrix{Target}, SparseMatrix{Target})

    ac(Vector{<:Input}, SparseVector{Target}, to_sparse(Target, Input))
    ac(Matrix{<:Input}, SparseMatrix{Target}, to_sparse(Target, Input))

    # Don't shadow the identity case, which should return an alias of the input.
    ac(SparseVector{Target}, SparseVector{Target}, identity)
    ac(SparseMatrix{Target}, SparseMatrix{Target}, identity)
end

function ac_all(Target, Input)
    ac_dense(Target, (Input, Target))
    ac_sparse(Target, Input)
end

ac_all(Float64, Real)
ac_all(Int64, Integer)
ac_all(Bool, Integer)

# ==========================================================================================
# Try successive conversions until one succeeds, applying the corresponding function then.

function input_try(input, tries...) # [(Type, Function(conversion_result) -> _)]
    for (T, then) in tries
        x = try
            inputconvert(T, input)
        catch e
            e isa InputError || rethrow(e)
            continue
        end
        return then(x)
    end
    mess = IOBuffer()
    print(mess, "Cannot convert input to either:")
    for (T, _) in tries
        print(mess, "\n  - $T")
    end
    print(mess, "\nReceived value: $(repr(input)) ::$(typeof(input)).")
    mess = String(take!(mess))
    inerr(mess)
end

# ==========================================================================================
# Execute one or the other block named by end user.
function from_name(input, tries...) # [(Symbol, Function() -> _)]
    name = inputconvert(Symbol, input)
    expected = Symbol[]
    for (attempt, fn) in tries
        name == attempt && return fn()
        push!(expected, attempt)
    end
    inerr("Expected one of [$(EN.join_elided(expected, ", ", " or "))], \
           received instead: $(repr(input))")
end
