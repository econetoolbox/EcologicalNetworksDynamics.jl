# Gather all default implementations for the dataflow pipelines,
# with correct reports upgrades on failure,
# and open up extension points for particular component.

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
convert(T::Type, input) = checkerr(input, "Conversion to `$T` not implemented.")
convert(::Type{T}, input::T) where {T} = input # Alias exact type.
# Extension points (specialize).
convert(T::Type, ::Dispatcher, input) = convert(T, input)
convert(T::Type, B::Type{<:Blueprint}, input) = convert(T, dispatcher(B), input)
convert(T::Type, b::Blueprint, input) = convert(T, typeof(b), input)

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

"Determine main blueprint data value and data type if any (expect *static* answer)."
# TODO: default to first field type?
datatype(B::Type{<:Blueprint}) = unimplemented(datatype, B)
datatype(bp::Blueprint) = typeof(data(bp))

# Get the core corresponding field type.
D.type(B::Type{<:Blueprint}) = D.type(dispatcher(B))

"Extract main blueprint data if any (expect *static* answer)."
data(b::Blueprint) = unimplemented(data, b) # TODO: default to first field?

"""
Guarded entrypoint into blueprint construction.
Transform raw input into blueprint data. Return a *tuple* to be passed to new(...).
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

"Guarded framework entrypoint for correct error upgrade."
bp_construct(B::Type{<:Blueprint}, args...; kwargs...) =
    try
        construct(B, args...; kwargs...)
    catch e
        e isa CheckError || rethrow(e)
        e.d = dispatcher(B)
        rethrow(BlueprintError(B, :construct, e))
    end

#-------------------------------------------------------------------------------------------
# Early check.

"Validate data and take this opportunity to start lowering."
early_check(d::Dispatcher, data) = intrinsic_check(d, data)
early_check(B::Type{<:Blueprint}, data) = early_check(dispatcher(B), data)
early_check(b::Blueprint) = early_check(typeof(b), data(b))

"Guarded entrypoint for the blueprint pipeline."
bp_early_check(b::Blueprint) =
    try
        early_check(b)
    catch e
        e isa CheckError || rethrow(e)
        B = typeof(b)
        e.d = dispatcher(b)
        rethrow(BlueprintError(B, :early, e))
    end

#-------------------------------------------------------------------------------------------
# Late check.

"Use perform checks against an actual model value, continuing lowering."
late_check(::Model, ::Dispatcher, low) = low # Nothing checked by default.
late_check(m::Model, b::Blueprint, low) = late_check(m, dispatcher(b), low)

"Guarded entrypoint for the blueprint pipeline."
bp_late_check(m::Model, b::Blueprint, low) =
    try
        late_check(m, b, low)
    catch e
        e isa CheckError || rethrow(e)
        B = typeof(b)
        rethrow(BlueprintError(B, :late, e))
    end

#-------------------------------------------------------------------------------------------
# Lower.

"""
Final lowering stage, transforming data
into something compatible with internal storage for `expand!`.
Defaults to aliasing because lowering may have started before,
but be careful not to output data possibly still referenced by user.
"""
lower(::Model, ::Dispatcher, late_data) = late_data
lower(m::Model, b::Blueprint, ld) = lower(m, dispatcher(b), ld)

#-------------------------------------------------------------------------------------------
# Expand.

"Use `lower`ed data to finally expand into the desired component. Cannot fail."
expand!(m::Model, d::Dispatcher, low) = unimplemented(expand!, m, d, low)
expand!(m::Model, b::Blueprint, low) = expand!(m, dispatcher(b), low)

# ==========================================================================================
# Query values.

"Given a checked reference to inner model data, obtain a copy of it."
obtain(m::Model, d::Dispatcher, mref) = unimplemented(obtain, m, d, mref)

# Redirect cartesian index like the underlying tuple.
obtain(m::Model, d::Dispatcher, c::CartesianIndex) = obtain(m, d, Tuple(c))

# ==========================================================================================
# Mutate/Reassign.

"""
Default lowering pipeline from raw input to the data to be modified.
The query is assumed to have been checked.
"""
function mut_lower(m::Model, d::Dispatcher, _mref, rhs)
    T = D.type(d)
    conv = convert(T, d, rhs)
    early = early_check(d, conv)
    late = late_check(m, d, early)
    low = lower(m, d, late)
    low
end

"Actually perform mutation, assuming checked model reference (query) and lowered data."
mutate!(m::Model, d::Dispatcher, mref, low) = unimplemented(mutate!, m, d, mref, low)

"Guarded entrypoint for the mutation pipeline."
function mut_set!(m::Model, d::Dispatcher, query, rhs)
    mref = Query.check(m, d, query)
    low = try
        mut_lower(m, d, mref, rhs)
    catch e
        e isa CheckError || rethrow(e)
        e.d = d
        if isnothing(e.uref)
            e.uref = query
        end
        if isnothing(e.mref)
            e.mref = mref
        end
        rethrow(MutationError(e))
    end
    mutate!(m, d, mref, low)
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
    F.define_blueprint(B, shortline; depends)
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
        F.early_check(b::$B) = NF.bp_early_check(b)
        F.late_check(m::Model, b::$B, data) = NF.bp_late_check(m, b, data)
        F.expand!(m::Model, b::$B, data) = NF.expand!(m, b, data)
    end)
    isnothing(d) && return
    eval(quote
        NF.dispatcher(::Type{$B}) = $d
    end)
end

"Inject default constructor into a blueprint struct."
macro bp_construct(B)
    B = esc(B)
    quote
        $B(args...; kwargs...) = new($NF.bp_construct($B, args...; kwargs...)...)
    end
end
