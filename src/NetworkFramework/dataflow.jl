# Describe here the typical, default data flow, starting from arbitrary user input:
#
#   - Parse:
#       - Convert (to the right type).
#       - Intrinsic check.
#   - (Data)Blueprint:
#     - Construct: parse.
#     - Early check: intrinsic check (again) + data preprocess.
#     - Late check (against model).
#     - Expand.
#   - (Data)Component (via *views*):
#     - Index:
#         - Check dimension.
#         - Parse (index).
#         - Check query (against model).
#         - Obtain.
#     - Mutate:
#         - Select: index (before 'obtain').
#         - Parse (rhs).
#         - Early check.
#         - Late check.
#         - Commit.
#
# Throughout the process, raise and upgrade the typical error types
# to explain failure reason and upgrade context depending on position within the flow.
# Authors should be able to focus on the core failur reason,
# and assume that additional context *will* be introduced above to improve the error report.

#-------------------------------------------------------------------------------------------
# Open up specialisation opportunities.

dispatcher(::Type{<:Blueprint}) = throw("unimplemented")
dispatcher(b::Blueprint) = b |> typeof |> dispatcher

#-------------------------------------------------------------------------------------------
# Convert.

"""
Specify allowed input conversion to the desired types in the context of the library.
/!\\ Differs from julia's `Base.convert`.
No conversion happens but *aliasing* instead if the input type is already the one desired.
"""
convert(T::Type, input) = liberr(T, input, "Conversion not implemented.")
convert(::Type{T}, input::T) where {T} = input # Alias exact type.
# Specialization opportunities.
convert(T::Type, ::D.Dispatcher, input) = convert(T, input)
convert(T::Type, B::Type{<:Blueprint}, input) = convert(T, dispatcher(B), input)
convert(T::Type, b::Blueprint, input) = convert(T, dispatcher(b), input)

#-------------------------------------------------------------------------------------------
# Intrinsic check.

"""
Assuming input already has the right type,
check that the value is consistent with expectations.
Return the aliased passed data unchanged.
"""
intrinsic_check(::D.Dispatcher, data) = data # Nothing to check *a priori*.
intrinsic_check(B::Type{<:Blueprint}, data) = intrinsic_check(dispatcher(B), data)
intrinsic_check(b::Blueprint) = intrinsic_check(typeof(b), data(b))

# Default entrypoint from automatic.

#-------------------------------------------------------------------------------------------
# Parse.

"""
Perform conversion and intrinsic check at once.
/!\\ Differs from julia's `Base.parse`.
"""
function parse(T::Type, d, input)
    data = convert(T, d, input)
    intrinsic_check(d, data)
end

#-------------------------------------------------------------------------------------------
# Construct.

"""
Determine main blueprint data type, if any (expect *static* answer).
"""
datatype(::Type{<:Blueprint}) = throw("unimplemented")
datatype(bp::Blueprint) = typeof(data(bp))

"""
Constructing blueprint data from raw input.
"""
construct(B::Type{<:Blueprint}, input) = parse(B, datatype(B), input) # Default.

# Actual framework entrypoint to inject error handling.
_construct(B::Type{<:Blueprint}, args...; kwargs...) =
    fwd_err(construct, B, args...; kwargs...) do err
        d = dispatcher(B)
        "When constructing blueprint for $d:\n$err"
    end

#-------------------------------------------------------------------------------------------
# Early check.

"""
Extract main blueprint data, if any (expect trivial O(1) aliasing access).
"""
data(::Blueprint) = throw("unimplemented")

"""
Perform intrinsic check (again) as an early stage of expansion.
Necessary because the blueprint may have mutated since last intrinsic check (construction).
Can take this opportunity to collect / construct extra data for later expansion stages.
Return data for late_check.
"""
early_check(b::Blueprint) = intrinsic_check(b, data(b)) # Default.

# Framework entrypoint.
_early_check(b::Blueprint) =
    fwd_err(early_check, b) do err
        d = dispatcher(b)
        "When checking $d blueprint data:\n$err"
    end

#-------------------------------------------------------------------------------------------
# Late check.

"""
Use early_check data to perform checks against an actual model value.
Can take this opportunity to collect / construct extra data for later expansion stages.
Return data for expand!.
"""
late_check(::Model, ::Blueprint, data) = data # Nothing checked by default.

# Framework entrypoint.
_late_check(m::Model, b::Blueprint, data) =
    fwd_err(late_check, m, b, data) do err
        d = dispatcher(d)
        "When checking $d blueprint against model:\n$err"
    end

#-------------------------------------------------------------------------------------------
"""
Use late_check data to finally expand into the desired component.
Cannot fail.
"""
expand!(::Model, ::Blueprint, data) = throw("unimplemented")

# ==========================================================================================
"""
Register a given exotic blueprint into the above.
"""
function register_blueprint(B::Type{<:Blueprint}, shortline::String)
    NF.define_blueprint(B, shortline)
    eval(quote
        $B(args...; kwargs...) = $NF._construct($B, args...; kwargs...)
        $F.early_check(b::$B) = $NF._early_check(b)
        $F.late_check(m::Model, b::$B, data) = $NF._late_check(m, b, data)
        $F.expand!(m::Model, b::$B, data) = $NF.expand!(m, b, data)
    end)
end
