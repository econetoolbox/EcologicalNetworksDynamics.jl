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
# Generic default behaviour.
convert(T::Type, input) = converr(T, input, "Conversion not implemented.")
convert(T::Type, ::Dispatcher, input) = convert(T, input)
convert(T::Type, BP::Type{<:Blueprint}, input) = convert(T, dispatcher(BP), input)
convert(d::Dispatcher, input) = convert(D.type(d), d, input)

"Guarded entrypoint for mutation."
mut_convert(d::Dispatcher, input) =
    try
        convert(d, input)
    catch e
        e isa LibError || rethrow(e)
        e = CheckError(e)
        e.d = d
        rethrow(e)
    end

#-------------------------------------------------------------------------------------------
# Early check.

"Default early check, for either pipeline."
early_check(::Dispatcher, data) = data # Defaults to just accepting & aliasing the value.

"Early check for blueprint construction: must alias."
cst_early_check(BP::Type{<:Blueprint}, data) = early_check(dispatcher(BP), data)

"Early check for blueprint expansion: may start lowering."
bp_early_check(bp::Blueprint) = cst_early_check(typeof(bp), data(bp))

"Early check for mutation: may start lowering."
mut_early_check(d::Dispatcher, data) = early_check(d, data)

"Guarded entrypoint for the blueprint pipeline."
_bp_early_check(bp::Blueprint) = # Entry point: the framework calls in there.
    try
        bp_early_check(bp) # Extension point: authors specialize this.
    catch e
        e isa CheckError || rethrow(e)
        B = typeof(bp)
        e.d = dispatcher(bp)
        rethrow(BlueprintError(B, :early, e))
    end

#-------------------------------------------------------------------------------------------
# "Construct blueprint" entrypoint.

"""
Determine main blueprint data value and data type if any (expect *static* answer).
Defaults to first field type.
"""
datatype(BP::Type{<:Blueprint}) = first(fieldtypes(BP))
datatype(bp::Blueprint) = typeof(data(bp))

"""
Extract main blueprint data if any (expect *static* answer).
Defaults to first field.
"""
data(bp::Blueprint) = getfield(bp, first(fieldnames(typeof(bp))))

# Get the core corresponding field type.
D.type(BP::Type{<:Blueprint}) = D.type(dispatcher(BP))

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
        println(io, ":")
        render_input(io, unexp)
    end
    isempty(rest) || errwith(err(rest), "Unexpected arguments to blueprint constructor:")
    isempty(kwargs) ||
        errwith(err(kwargs), "Unexpected keyword arguments to blueprint constructor:")
    T = datatype(BP)
    data = convert(T, BP, input)
    (cst_early_check(BP, data),)
end

"Guarded framework entrypoint for correct error upgrade."
_construct(BP::Type{<:Blueprint}, args...; kwargs...) =
    try
        construct(BP, args...; kwargs...)
    catch e
        e isa LibError || rethrow(e)
        e = CheckError(e)
        e.d = dispatcher(BP)
        rethrow(BlueprintError(BP, :construct, e))
    end

#-------------------------------------------------------------------------------------------
# Late check.

"Default late check, for either pipeline."
late_check(::Model, ::Dispatcher, early) = early # Default to just accept & alias.

"Late check for blueprint expansion."
bp_late_check(md::Model, bp::Blueprint, early) = late_check(md, dispatcher(bp), early)

"Late check for mutation."
mut_late_check(md::Model, d::Dispatcher, _ref, early) = late_check(md, d, early)

"Guarded entrypoint for the blueprint pipeline."
_bp_late_check(md::Model, bp::Blueprint, early) =
    try
        bp_late_check(md, bp, early)
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

"Default lowering, for either pipeline."
lower(::Model, ::Dispatcher, late) = late # Default to just accept & alias.

"Lowering for blueprint expansion."
bp_lower(md::Model, bp::Blueprint, late) = lower(md, dispatcher(bp), late)

"Lowering for mutation."
mut_lower(md::Model, d::Dispatcher, _ref, ld) = lower(md, d, ld)

#-------------------------------------------------------------------------------------------
# Expand.

"Final stage of blueprint expansion."
expand!(md::Model, d::Dispatcher, low) = unimplemented(expand!, md, d, low)
expand!(md::Model, bp::Blueprint, late) =
    expand!(md, dispatcher(bp), NF.bp_lower(md, bp, late))

# ==========================================================================================
# Query values.

"""
    obtain(md::Model, d::Dispatcher, mref)
    obtain(vw::AbstractView, mref)

Given a checked reference to inner model data, obtain a copy of it. Cannot fail.
"""
function obtain end

# ==========================================================================================
# Mutate/Reassign.

"""
Actually perform mutation, assuming checked model reference (query) and lowered data.
Cannot fail.
"""
mutate!(md::Model, d::Dispatcher, mref, low) = unimplemented(mutate!, md, d, mref, low)

"""
Guarded entrypoint into the whole mutation pipeline,
with trusted `ref` query (local indices).
"""
const TrustedRef = Union{Tuple{Int},Tuple{Int,Int},_WholeData}
function mut_set!(md::Model, d::Dispatcher, ref::TrustedRef, rhs)
    low = try
        conv = mut_convert(d, rhs)
        early = mut_early_check(d, conv)
        late = mut_late_check(md, d, ref, early)
        low = mut_lower(md, d, ref, late)
        low
    catch e
        e isa LibError || rethrow(e)
        e = CheckError(e)
        e.d = d
        e.mref = complete_mref(ref, md, d)
        rethrow(MutationError(e))
    end
    mutate!(md, d, ref, low)
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
        F.early_check(bp::$BP) = NF._bp_early_check(bp)
        F.late_check(md::Model, bp::$BP, data) = NF._bp_late_check(md, bp, data)
        F.expand!(md::Model, bp::$BP, late) = NF.expand!(md, bp, late)
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
        $BP(args...; kwargs...) = $new($NF._construct($BP, args...; kwargs...)...)
    end
end
