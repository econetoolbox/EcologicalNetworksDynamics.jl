# Gather all default implementations for the dataflow pipelines,
# with correct reports upgrades on failure,
# and open up extension points for particular component.

"If relevant, obtain the data kind provided by the blueprint."
selector(BP::Type{<:Blueprint}) = unimplemented(selector, BP)
selector(bp::Blueprint) = bp |> typeof |> selector

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
convert(T::Type, ::Selector, input) = convert(T, input)
convert(T::Type, BP::Type{<:Blueprint}, input) = convert(T, selector(BP), input)
convert(s::Selector, input) = convert(SL.type(s), s, input)

"Guarded entrypoint for mutation."
mut_convert(s::Selector, input) =
    try
        convert(s, input)
    catch e
        e isa LibError || rethrow(e)
        e = CheckError(e)
        e.s = s
        rethrow(e)
    end

#-------------------------------------------------------------------------------------------
# Early check.

"Default early check, for either pipeline."
early_check(::Selector, data) = data # Defaults to just accepting & aliasing the value.

"""
Early check for blueprint construction: must alias.
(only useful if relying on the default `construct` implementation)
"""
cst_early_check(BP::Type{<:Blueprint}, data) = early_check(selector(BP), data)

"Early check for blueprint expansion: may start lowering."
bp_early_check(bp::Blueprint) = cst_early_check(typeof(bp), data(bp))

"Early check for mutation: may start lowering."
mut_early_check(s::Selector, data) = early_check(s, data)

"Guarded entrypoint for the blueprint pipeline."
_bp_early_check(bp::Blueprint) = # Entry point: the framework calls in there.
    try
        bp_early_check(bp) # Extension point: authors specialize this.
    catch e
        e isa CheckError || rethrow(e)
        B = typeof(bp)
        e.s = selector(bp)
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
SL.type(BP::Type{<:Blueprint}) = SL.type(selector(BP))

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
        e.s = selector(BP)
        rethrow(BlueprintError(BP, :construct, e))
    end

#-------------------------------------------------------------------------------------------
# Late check.

"Default late check, for either pipeline."
late_check(::Model, ::Selector, early) = early # Default to just accept & alias.

"Late check for blueprint expansion."
bp_late_check(md::Model, bp::Blueprint, early) = late_check(md, selector(bp), early)

"Late check for mutation."
mut_late_check(md::Model, s::Selector, early) = late_check(md, s, early)
mut_late_check(md::Model, s::Selector, _iref, early) = mut_late_check(md, s, early)

"Guarded entrypoint for the blueprint pipeline."
_bp_late_check(md::Model, bp::Blueprint, early) =
    try
        bp_late_check(md, bp, early)
    catch e
        e isa CheckError || rethrow(e)
        B = typeof(bp)
        if isnothing(e.s)
            e.s = selector(bp)
        end
        if e.ref === UserRef(wholedata)
            e.ref = ModelRef(wholedata)
        end
        rethrow(BlueprintError(B, :late, e))
    end

#-------------------------------------------------------------------------------------------
# Lower.
# TODO: is it actually useful/used to have it stand within the pipeline?
# Maybe `expand` can do / is doing just that.

"Default lowering, for either pipeline."
lower(::Model, ::Selector, late) = late # Default to just accept & alias.

"Lowering for blueprint expansion."
bp_lower(md::Model, bp::Blueprint, late) = lower(md, selector(bp), late)

"Lowering for mutation."
mut_lower(md::Model, s::Selector, _ref, ld) = lower(md, s, ld)

#-------------------------------------------------------------------------------------------
# Expand.

"Final stage of blueprint expansion."
expand!(md::Model, s::Selector, low) = unimplemented(expand!, md, s, low)
expand!(md::Model, bp::Blueprint, late) =
    expand!(md, selector(bp), IT.bp_lower(md, bp, late))

# ==========================================================================================
# Query values.

"""
    obtain(md::Model, s::Selector, mref)
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
mutate!(md::Model, s::Selector, mref, low) = unimplemented(mutate!, md, s, mref, low)

"""
Guarded entrypoint into the whole mutation pipeline,
with trusted `ref` query (local indices).
"""
const TrustedIndexRef = Union{Tuple{Int},Tuple{Int,Int},WholeData}
function mut_set!(md::Model, s::Selector, iref::TrustedIndexRef, rhs)
    low = try
        conv = mut_convert(s, rhs)
        early = mut_early_check(s, conv)
        late = mut_late_check(md, s, iref, early)
        low = mut_lower(md, s, iref, late)
        low
    catch e
        e isa LibError || rethrow(e)
        e = CheckError(e)
        e.s = s
        if e.ref === UserRef(wholedata)
            e.ref = to_mref(iref, md, s)
        end
        rethrow(MutationError(e))
    end
    mutate!(md, s, iref, low)
    rhs # (julia habit)
end

# ==========================================================================================
"Register a given exotic blueprint into the above."
function register_blueprint(
    BP::Type{<:Blueprint},
    shortline::String;
    s = nothing,
    implied = [],
    depends = [],
)
    CS.define_blueprint(BP, shortline; depends)
    if !isempty(implied) > 0
        eval(quote
            CS.implied(::$BP) = $implied
        end)
        for cpi in implied
            CPI = typeof(cpi)
            eval(
                quote
                    CS.implied_blueprint_for(bp::$BP, ::Type{$CPI}) =
                        IT.implied($s, $cpi, bp)
                end,
            )
        end
    end
    eval(quote
        CS.early_check(bp::$BP) = IT._bp_early_check(bp)
        CS.late_check(md::Model, bp::$BP, data) = IT._bp_late_check(md, bp, data)
        CS.expand!(md::Model, bp::$BP, late) = IT.expand!(md, bp, late)
    end)
    isnothing(s) && return
    eval(quote
        IT.selector(::Type{$BP}) = $s
    end)
end

"Inject default constructor into a blueprint struct."
macro bp_construct(BP)
    BP, new = esc.((BP, :new))
    quote
        $BP(args...; kwargs...) = $new($IT._construct($BP, args...; kwargs...)...)
    end
end
