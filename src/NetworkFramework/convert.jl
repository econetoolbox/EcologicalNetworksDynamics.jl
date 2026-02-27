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
inputconvert(::Type, input) = input # Default to identity.

# ==========================================================================================
# Scalar conversions.
macro allow_convert(Input, Target, f)
    esc(quote
        inputconvert(::Type{$Target}, v::$Input) = $f(v)
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

macro allow_convert_all(Input, Target)
    esc(
        quote
        #! format: off
        @allow_convert $Input                 $Target               $Target
        @allow_convert Vector{<:$Input}       Vector{$Target}       Vector{$Target}
        @allow_convert Matrix{<:$Input}       Matrix{$Target}       Matrix{$Target}
        @allow_convert SparseVector{<:$Input} SparseVector{$Target} SparseVector{$Target}
        @allow_convert SparseMatrix{<:$Input} SparseMatrix{$Target} SparseMatrix{$Target}

        @allow_convert(
            Vector{<:$Input},
            SparseVector{$Target},
            v -> SparseVector{$Target}(sparse(v)),
        )
        @allow_convert(
            Matrix{<:$Input},
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
    mess = String(take!(mess))
    inerr(mess)
end
