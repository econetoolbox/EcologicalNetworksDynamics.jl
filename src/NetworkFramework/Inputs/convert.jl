"""
Without any context, call with a target type to convert input.
"""
absorb(::Type, input) = input # Default to identity.

# ==========================================================================================
# Scalar conversions.
macro allow_convert(Input, Target, f)
    esc(quote
        absorb(::Type{$Target}, v::$Input) = $f(v)
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
