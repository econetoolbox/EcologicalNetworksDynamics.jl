# Open up extension points by providing specialization opportunities.

"If relevant, obtain the data kind provided by the blueprint."
dispatcher(B::Type{<:Blueprint}) = unimplemented(dispatcher, B)
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
# Construct.

"Determine main blueprint data value and data type if any (expect *static* answer)."
# TODO: default to first field type?
datatype(B::Type{<:Blueprint}) = unimplemented(datatype, B)
datatype(bp::Blueprint) = typeof(data(bp))

# Get the core corresponding field type.
D.type(B::Type{<:Blueprint}) = D.type(dispatcher(B))

"Extract main blueprint data if any (expect *static* answer)."
data(b::Blueprint) = unimplemented(data, b) # TODO: default to first field?

"""
Transform raw input into blueprint data.
Return a *tuple* to be passed to new(...).
"""
function construct(B::Type{<:Blueprint}, args...; kwargs...)
    # Not sure how to guard against that with dispatching
    # without breaking per-blueprint specialization.
    input, rest... = args
    err(unexp) = io -> begin
        print(io, "in ")
        bpcol(io, B)
        print(io, ":")
        render_input(io, unexp)
    end
    isempty(rest) || errwith(err(rest), "Unexpected arguments to blueprint constructor:")
    isempty(kwargs) ||
        errwith(err(kwargs), "Unexpected keyword arguments to blueprint constructor:")
    T = datatype(B)
    data = convert(T, B, input)
    (intrinsic_check(B, data),)
end

# Actual framework entrypoint to inject error handling.
_construct(B::Type{<:Blueprint}, args...; kwargs...) =
    try
        construct(B, args...; kwargs...)
    catch e
        e isa LibError || rethrow(e)
        upgrade(e, BlueprintError, (nothing,), B, :construct, nothing)
    end

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

# Collections: default to checking every value independenly.
# (It has been checked that the compiler is eliding the whole loop
# in case `intrinsic_check` is defaulting to noop.)
function intrinsic_check(d::Dispatcher, data::AbstractArray)
    for (i, v) in pairs(data)
        try
            intrinsic_check(d, v)
        catch e
            e isa LibError || rethrow(e)
            upgrade(e, RefErr, i)
        end
    end
    data
end

#-------------------------------------------------------------------------------------------
# Early check.

"Validate data and take this opportunity to start lowering."
early_check(d::Dispatcher, data) = intrinsic_check(d, data)
early_check(b::Blueprint) = early_check(dispatcher(b), data(b))

# Framework entrypoint.
_early_check(b::Blueprint) =
    try
        early_check(b)
    catch e
        e isa LibError || rethrow(e)
        upgrade(e, BlueprintError, (nothing,), typeof(b), :early, nothing)
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
        upgrade(e, BlueprintError, (WholeInput(),), typeof(b), :late, m)
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

"Use `lower` data to finally expand into the desired component. Cannot fail."
expand!(m::Model, d::Dispatcher, t) = unimplemented(expand!, m, d, t)
expand!(m::Model, b::Blueprint, data) = expand!(m, dispatcher(b), data)
expand!(m::Model, b::Blueprint) = expand!(m, dispatcher(b), data(b))

#-------------------------------------------------------------------------------------------
# Reassign.

"Default lowering pipeline from raw input to the data to be reassigned."
function reassign(m::Model, d::Dispatcher, input)
    T = D.type(d)
    conv = NF.convert(T, d, input)
    early = early_check(d, conv)
    late = late_check(m, d, early)
    low = lower(m, d, late)
    low
end

"Actually perform the reassignment, assuming lowered data."
reassign!(m::Model, d::Dispatcher, t) = unimplemented(reassign!, m, d, t)

# Entrypoint from generated code.
function _reassign(m::Model, d::Dispatcher, input)
    try
        reassign(m, d, input)
    catch e
        e isa LibError || rethrow(e)
        upgrade(e, MutationError, (WholeInput(),), d, :assign, m)
    end
end

# ==========================================================================================
"Register a given exotic blueprint into the above."
function register_blueprint(
    B::Type{<:Blueprint},
    shortline::String;
    d = nothing,
    implied = (),
    depends = [],
)
    NF.define_blueprint(B, shortline; depends)
    if !isempty(implied) > 0
        eval(quote
            F.implied(::$B) = $implied
        end)
        for i in implied
            I = typeof(i)
            eval(
                quote
                    F.implied_blueprint_for(b::$B, ::Type{$I}) =
                        NF.implied_class($d, $i, b)
                end,
            )
        end
    end
    eval(quote
        F.early_check(b::$B) = $NF._early_check(b)
        F.late_check(m::Model, b::$B, data) = $NF._late_check(m, b, data)
        F.expand!(m::Model, b::$B, data) = $NF.expand!(m, b, data)
    end)
    isnothing(d) && return
    eval(quote
        NF.dispatcher(::Type{$B}) = $d
    end)
end

"Inject default constructor into a blueprint struct."
macro bp_construct(B)
    quote
        $B(args...; kwargs...) = new($NF._construct($B, args...; kwargs...)...)
    end |> esc
end
