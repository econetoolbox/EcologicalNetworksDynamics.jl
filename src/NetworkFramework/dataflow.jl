# Open up extension points by providing specialization opportunities.

"""
If relevant, obtain the data kind provided by the blueprint.
"""
dispatcher(::Type{<:Blueprint}) = throw("unimplemented")
dispatcher(b::Blueprint) = b |> typeof |> dispatcher

#-------------------------------------------------------------------------------------------
# Convert.

"""
/!\\ Not julia's `Base.convert`.
Specify allowed input conversion to the desired types in the context of the library.
The expected type is either a component-author defined *scalar* type
(=one value per graph, per node or per edge),
or a hardcoded, framework-defined aggregation of these into dense/sparse arrays
or maps and adjacency lists.
Following julia's behaviour:
*alias* instead of converting if the input type is already the one desired.
"""
convert(T::Type, input) = converr(T, input, "Conversion not implemented.")
convert(::Type{T}, input::T) where {T} = input # Alias exact type.
# Extension points (specialize).
convert(T::Type, ::Dispatcher, input) = convert(T, input)
convert(T::Type, B::Type{<:Blueprint}, input) = convert(T, dispatcher(B), input)
convert(T::Type, b::Blueprint, input) = convert(T, dispatcher(b), input)

#-------------------------------------------------------------------------------------------
# Intrinsic check.

"""
Assuming input data already has the right type,
check that the value is consistent with expectations.
Return the passed data aliased and unchanged.
"""
intrinsic_check(::Dispatcher, data) = data # Nothing to check *a priori*.
intrinsic_check(B::Type{<:Blueprint}, data) = intrinsic_check(dispatcher(B), data)
intrinsic_check(b::Blueprint) = intrinsic_check(typeof(b), data(b))

#-------------------------------------------------------------------------------------------
# Construct.

"Determine main blueprint data type if any (expect *static* answer)."
datatype(::Type{<:Blueprint}) = throw("unimplemented")
datatype(bp::Blueprint) = typeof(data(bp))

"""
Transform raw input into blueprint data.
Return a *tuple* to be passed to new(...).
"""
function construct(B::Type{<:Blueprint}, input)
    T = datatype(B)
    data = convert(T, B, input)
    intrinsic_check(B, data)
end

# Actual framework entrypoint to inject error handling.
_construct(B::Type{<:Blueprint}, args...; kwargs...) =
    try
        construct(B, args...; kwargs...)
    catch e
        e isa LibError || rethrow(e)
        upgrade(e, BlueprintError, (nothing,), :construct, nothing)
    end

#-------------------------------------------------------------------------------------------
# Early check.

"Extract main blueprint data if any (expect *static* answer)."
data(::Blueprint) = throw("unimplemented")

"Validate data and take this opportunity to start lowering."
early_check(d::Dispatcher, data) = intrinsic_check(d, data)
early_check(b::Blueprint) = early_check(dispatcher(b), data(b))

# Framework entrypoint.
_early_check(b::Blueprint) =
    try
        early_check(b, data(b))
    catch e
        e isa LibError || rethrow(e)
        upgrade(e, BlueprintError, (nothing,), :early_check, nothing)
    end

#-------------------------------------------------------------------------------------------
# Late check.

"Use perform checks against an actual model value, continuing lowering."
late_check(::Model, ::Dispatcher, early_data) = early_data # Nothing checked by default.
late_check(m::Model, b::Blueprint, ed) = late_check(m, dispatcher(b), ed)

# Framework entrypoint.
_late_check(m::Model, b::Blueprint, data) =
    try
        late_check(m, b, data)
    catch e
        e isa LibError || rethrow(e)
        upgrade(e, BlueprintError, (WholeInput(),), :late_check, m)
    end

#-------------------------------------------------------------------------------------------
# Lower.

"""
Final lowering stage, transforming data
into something compatible with internal storage for `expand!`.
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

"Default lowering pipeline from raw input to the data to be reassigned."
reassign(::Model, ::Dispatcher, _) = throw("unimplemented")

# Entrypoint from generated code.
function _reassign(m::Model, d::Dispatcher, input)
    T = D.type(d)
    try
        conv = convert(T, d, input)
        early = early_check(d, conv)
        late = late_check(m, d, early)
        low = lower(m, d, late)
        low
    catch e
        e isa LibError || rethrow(e)
        upgrade(e, MutationError, (WholeInput(),), d, :assign, m)
    end
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
