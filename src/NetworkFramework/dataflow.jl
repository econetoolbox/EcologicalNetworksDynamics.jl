# Gather all default implementations for the dataflow pipelines,
# with correct reports upgrades on failure,
# and open up extension points for particular component.

"If relevant, obtain the data kind provided by the blueprint."
dispatcher(BP::Type{<:Blueprint}) = unimplemented(dispatcher, BP)
dispatcher(bp::Blueprint) = bp |> typeof |> dispatcher

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
# Extension points (specialize).
convert(T::Type, ::Dispatcher, input) = convert(T, input)
convert(T::Type, BP::Type{<:Blueprint}, input) = convert(T, dispatcher(BP), input)
convert(T::Type, bp::Blueprint, input) = convert(T, typeof(bp), input)

#-------------------------------------------------------------------------------------------
# Intrinsic check.

"""
Assuming input data already has the right type,
check that the value is consistent with expectations.
Return the passed data aliased and unchanged.
"""
intrinsic_check(::Dispatcher, data) = data # Nothing to check *a priori*.
intrinsic_check(BP::Type{<:Blueprint}, data) = intrinsic_check(dispatcher(BP), data)
intrinsic_check(bp::Blueprint) = intrinsic_check(typeof(bp), data(bp))

#-------------------------------------------------------------------------------------------
# Construct.

"Determine main blueprint data value and data type if any (expect *static* answer)."
# TODO: default to first field type?
datatype(BP::Type{<:Blueprint}) = unimplemented(datatype, BP)
datatype(bp::Blueprint) = typeof(data(bp))

# Get the core corresponding field type.
D.type(BP::Type{<:Blueprint}) = D.type(dispatcher(BP))

"Extract main blueprint data if any (expect *static* answer)."
data(bp::Blueprint) = unimplemented(data, bp) # TODO: default to first field?

"""
Guarded entrypoint into blueprint construction.
Transform raw input into blueprint data. Return a *tuple* to be passed to new(...).
"""
function construct(BP::Type{<:Blueprint}, args...; kwargs...)
    # Not sure how to guard against that with dispatching
    # without breaking per-blueprint specialization.
    input, rest... = args
    err(unexp) = io -> begin
        print(io, "in ")
        bpcol(io, BP)
        print(io, ":")
        render_input(io, unexp)
    end
    isempty(rest) || errwith(err(rest), "Unexpected arguments to blueprint constructor:")
    isempty(kwargs) ||
        errwith(err(kwargs), "Unexpected keyword arguments to blueprint constructor:")
    T = datatype(BP)
    data = convert(T, BP, input)
    (intrinsic_check(BP, data),)
end

"Guarded framework entrypoint for correct error upgrade."
bp_construct(BP::Type{<:Blueprint}, args...; kwargs...) =
    try
        construct(BP, args...; kwargs...)
    catch e
        e isa LibError || rethrow(e)
        e = CheckError(e)
        e.d = dispatcher(BP)
        rethrow(BlueprintError(BP, :construct, e))
    end

#-------------------------------------------------------------------------------------------
# Early check.

"Validate data and take this opportunity to start lowering."
early_check(d::Dispatcher, data) = intrinsic_check(d, data)
early_check(BP::Type{<:Blueprint}, data) = early_check(dispatcher(BP), data)
early_check(bp::Blueprint) = early_check(typeof(bp), data(bp))

"Guarded entrypoint for the blueprint pipeline."
bp_early_check(bp::Blueprint) =
    try
        early_check(bp)
    catch e
        e isa CheckError || rethrow(e)
        B = typeof(bp)
        e.d = dispatcher(bp)
        rethrow(BlueprintError(B, :early, e))
    end

#-------------------------------------------------------------------------------------------
# Late check.

"Use perform checks against an actual model value, continuing lowering."
late_check(::Model, ::Dispatcher, low) = low # Nothing checked by default.
late_check(md::Model, bp::Blueprint, low) = late_check(md, dispatcher(bp), low)

"Guarded entrypoint for the blueprint pipeline."
bp_late_check(md::Model, bp::Blueprint, low) =
    try
        late_check(md, bp, low)
    catch e
        e isa CheckError || rethrow(e)
        B = typeof(bp)
        if isnothing(e.d)
            e.d = dispatcher(bp)
        end
        if isnothing(e.mref)
            e.mref = WholeData
        end
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
lower(md::Model, bp::Blueprint, ld) = lower(md, dispatcher(bp), ld)

#-------------------------------------------------------------------------------------------
# Expand.

"Use `lower`ed data to finally expand into the desired component. Cannot fail."
expand!(md::Model, d::Dispatcher, low) = unimplemented(expand!, md, d, low)
expand!(md::Model, bd::Blueprint, low) = expand!(md, dispatcher(bd), low)

# ==========================================================================================
# Query values.

"Given a checked reference to inner model data, obtain a copy of it."
obtain(md::Model, d::Dispatcher, mref) = unimplemented(obtain, md, d, mref)

# Redirect cartesian index like the underlying tuple.
obtain(md::Model, d::Dispatcher, c::CartesianIndex) = obtain(md, d, Tuple(c))

# ==========================================================================================
# Mutate/Reassign.

"""
Default lowering pipeline from raw input to the data to be modified.
The query is assumed to have been checked.
"""
function mut_lower(md::Model, d::Dispatcher, _mref, rhs)
    T = D.type(d)
    conv = convert(T, d, rhs)
    early = early_check(d, conv)
    late = late_check(md, d, early)
    low = lower(md, d, late)
    low
end

"Actually perform mutation, assuming checked model reference (query) and lowered data."
mutate!(md::Model, d::Dispatcher, mref, low) = unimplemented(mutate!, md, d, mref, low)

"Guarded entrypoint for the mutation pipeline."
function mut_set!(md::Model, d::Dispatcher, query, rhs)
    mref = Query.check(md, d, query)
    low = try
        mut_lower(md, d, mref, rhs)
    catch e
        e isa LibError || rethrow(e)
        e = CheckError(e)
        e.d = d
        if isnothing(e.uref)
            e.uref = query
        end
        if isnothing(e.mref)
            e.mref = mref
        end
        rethrow(MutationError(e))
    end
    mutate!(md, d, mref, low)
end

# ==========================================================================================
"Register a given exotic blueprint into the above."
function register_blueprint(
    BP::Type{<:Blueprint},
    shortline::String;
    d = nothing,
    implied = (),
    depends = [],
)
    F.define_blueprint(BP, shortline; depends)
    if !isempty(implied) > 0
        eval(quote
            F.implied(::$BP) = $implied
        end)
        for i in implied
            I = typeof(i)
            eval(
                quote
                    F.implied_blueprint_for(b::$BP, ::Type{$I}) =
                        NF.implied_class($d, $i, b)
                end,
            )
        end
    end
    eval(quote
        F.early_check(b::$BP) = NF.bp_early_check(b)
        F.late_check(m::Model, b::$BP, data) = NF.bp_late_check(m, b, data)
        F.expand!(m::Model, b::$BP, data) = NF.expand!(m, b, data)
    end)
    isnothing(d) && return
    eval(quote
        NF.dispatcher(::Type{$BP}) = $d
    end)
end

"Inject default constructor into a blueprint struct."
macro bp_construct(BP)
    BP, new = esc.((BP, :new))
    quote
        $BP(args...; kwargs...) = $new($NF.bp_construct($BP, args...; kwargs...)...)
    end
end
