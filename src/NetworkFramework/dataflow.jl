#-------------------------------------------------------------------------------------------
# Open up specialisation opportunities.

"""
If relevant, obtain the data kind provided by the blueprint.
"""
dispatcher(::Type{<:Blueprint}) = throw("unimplemented")
dispatcher(b::Blueprint) = b |> typeof |> dispatcher

#-------------------------------------------------------------------------------------------
# Convert.

"""
Specify allowed input conversion to the desired types in the context of the library.
/!\\ Differs from julia's `Base.convert`.
Following julia's behaviour:
*alias* instead of converting if the input type is already the one desired.
"""
convert(T::Type, input) = liberr(T, input, "Conversion not implemented.")
convert(::Type{T}, input::T) where {T} = input # Alias exact type.
# Specialization opportunities.
convert(T::Type, ::Dispatcher, input) = convert(T, input)
convert(T::Type, B::Type{<:Blueprint}, input) = convert(T, dispatcher(B), input)
convert(T::Type, b::Blueprint, input) = convert(T, dispatcher(b), input)

#-------------------------------------------------------------------------------------------
# Intrinsic check.

"""
Assuming input already has the right type,
check that the value is consistent with expectations.
Return the passed data aliased and unchanged.
"""
intrinsic_check(::Dispatcher, data) = data # Nothing to check *a priori*.
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

"Determine main blueprint data type if any (expect *static* answer)."
datatype(::Type{<:Blueprint}) = throw("unimplemented")
datatype(bp::Blueprint) = typeof(data(bp))

"""
Transform raw input into blueprint data.
Return a *tuple* to be passed to new(...).
"""
construct(B::Type{<:Blueprint}, input) = (parse(datatype(B), B, input),) # Default.

# Actual framework entrypoint to inject error handling.
_construct(B::Type{<:Blueprint}, args...; kwargs...) =
    fwd_err(construct, B, args...; kwargs...) do err
        d = dispatcher(B)
        "When constructing blueprint for $d:\n$err"
    end

#-------------------------------------------------------------------------------------------
# Early check.

"Extract main blueprint data if any (expect *static* answer)."
data(::Blueprint) = throw("unimplemented")

"""
Perform intrinsic check (again) as an early stage of expansion.
Necessary because the blueprint may have mutated since last intrinsic check (construction).
Return lowered data to `late_check`.
"""
early_check(d::Dispatcher, data) = intrinsic_check(d, data)
early_check(b::Blueprint) = early_check(dispatcher(b), data(b))

# Framework entrypoint.
_early_check(b::Blueprint) =
    fwd_err(early_check, b) do err
        d = dispatcher(b)
        "When checking $d blueprint data:\n$err"
    end

#-------------------------------------------------------------------------------------------
# Late check.

"""
Use `early_check` data to perform checks against an actual model value.
Return lowered data to `expand!`.
"""
late_check(::Model, ::Dispatcher, early_data) = early_data # Nothing checked by default.
late_check(m::Model, b::Blueprint, ed) = late_check(m, dispatcher(b), ed)

# Framework entrypoint.
_late_check(m::Model, b::Blueprint, data) =
    fwd_err(late_check, m, b, data) do err
        d = dispatcher(b)
        "When checking $d blueprint against model:\n$err"
    end

#-------------------------------------------------------------------------------------------
# Lower.

"""
Final lowering stage.
Transform `late_check` data into something compatible with internal storage for `expand!`.
Defaults to aliasing because lowering may have started before,
but be careful not to output data possibly referenced by user.
"""
lower(::Model, ::Dispatcher, late_data) = late_data
lower(m::Model, b::Blueprint, ld) = lower(m, dispatcher(b), ld)

#-------------------------------------------------------------------------------------------
# Expand.

"""
Use `lower` data to finally expand into the desired component.
Cannot fail.
"""
expand!(::Model, ::Dispatcher, _) = throw("unimplemented")
expand!(m::Model, b::Blueprint, data) = expand!(m, dispatcher(b), data)
expand!(m::Model, b::Blueprint) = expand!(m, dispatcher(b), data(b))


#-------------------------------------------------------------------------------------------
# Reassign.

"""
Whole lowering pipeline from raw input to the data to be reassigned.
"""
function reassign(m::Model, d::Dispatcher, input)
    T = D.type(d)
    conv = parse(T, d, input)
    early = early_check(d, conv)
    late = late_check(m, d, early)
    low = lower(m, d, late)
    low
end

# ==========================================================================================
"""
Register a given exotic blueprint into the above.
"""
function register_blueprint(B::Type{<:Blueprint}, shortline::String; d = nothing)
    NF.define_blueprint(B, shortline)
    eval(quote
        $F.early_check(b::$B) = $NF._early_check(b)
        $F.late_check(m::Model, b::$B, data) = $NF._late_check(m, b, data)
        $F.expand!(m::Model, b::$B, data) = $NF.expand!(m, b, data)
    end)
    isnothing(d) && return
    eval(quote
        $NF.dispatcher(::Type{$B}) = $d
    end)
end

"""
Inject default constructor into a blueprint struct.
"""
macro bp_construct(B)
    quote
        $B(args...; kwargs...) = new($NF._construct($B, args...; kwargs...)...)
    end |> esc
end
