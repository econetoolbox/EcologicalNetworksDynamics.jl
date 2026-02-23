# Use this file to factorize typical user input preprocessing:
# parsing, converting, intrinsic checking, contextualized checking, transforming..
# This is useful when:
#
#   - Constructing blueprints.
#   - Early-checking blueprints.
#   - Late-checking blueprints.
#   - Mutating data within the model.
#
# Functions defined here may be specialized as extension points,
# and raise `inerr("simple message")` on failure to obtain contextualized error messages.
# Typical (specializable) implementations for input checking
# at various stages of the data lifecycle within the model.

#-------------------------------------------------------------------------------------------
# Check without model information, against the target type.

check(::Dispatcher, T::Type, value) = inputconvert(T, value)
check_with_ref(d::Dispatcher, T::Type, value, i::Int) =
    try
        check(d, T, value)
    catch e
        e isa InputError || rethrow(e)
        inerr("At node index [$i]:\n$(e.mess)", rethrow)
    end
check_with_ref(d::Dispatcher, T::Type, value, l::Symbol) =
    try
        check(d, T, value)
    catch e
        e isa InputError || rethrow(e)
        inerr("At node with label $(repr(l)):\n$(e.mess)", rethrow)
    end

#-------------------------------------------------------------------------------------------
# Construct: any input is possible, but we don't know anything about the model yet.

construct(::Dispatcher, T::Type, value) = check(T, value)
construct_with_ref(d::NodeData, T::Type, value, r::Ref) = check_with_ref(d, T, value, r)
construct_from_iterable(d::NodeData, T::Type, iter) =
    try
        [construct_with_ref(d, T, value, i) for (i, value) in enumerate(iter)]
    catch e
        e isa InputError || rethrow(e)
        inerr("When constructing $d from iterable:\n$(e.mess)", rethrow)
    end
construct_from_map(d::NodeData, T::Type, map) =
    try
        parse(Map{<:Any,T}, map)
    catch e
        e isa InputError || rethrow(e)
        inerr("When constructing $d from map:\n$(e.mess)", rethrow)
    end

#-------------------------------------------------------------------------------------------
# Early-check: input has the correct blueprint type,
# but it may have been corrupted and we don't know anything about the model still.
# Construct checked data to be passed to late-checking.

function early_check(d::NodeData, vec::Vector)
    T = eltype(vec)
    data = T[]
    for (i, value) in enumerate(vec)
        try
            push!(data, check_with_ref(d, T, value, i))
        catch e
            e isa InputError || rethrow(e)
            inerr("When checking $d values array:\n$(e.message)", rethrow)
        end
    end
    data
end

function early_check(d::NodeData, map::Map)
    R, T = reftype(map), valtype(map)
    try
        parse(Map{R,T}, map) # Re-parse in case blueprint was mutated.
    catch e
        e isa InputError || rethrow(e)
        inerr("When checking $d values map:\n$(e.message)", rethrow)
    end
end

# ==========================================================================================
# Check against a model value, assuming the type and raw value is already correct.

check(::Dispatcher, ::Model, value) = value # Nothing to check by default.

function check_with_ref(d::NodeData, m::Model, value, i::Int, l::Symbol)
    try
        check(d, m, value, l)
    catch e
        e isa InputError || rethrow(e)
        inerr("At node with label $(repr(l)) ([$i]):\n$(e.mess)", rethrow)
    end
end

# Specialize the above, and automaticall infer any reference type from the other one.
function check_with_ref(d::NodeData, m::Model, value, i::Int)
    network = F.value(m)
    class = D.class(d)
    index = N.index(network, class)
    l = N.to_label(index, i)
    check_with_ref(d, value, m, l, i)
end
function check_with_ref(d::NodeData, m::Model, value, l::Symbol)
    network = F.value(m)
    class = D.class(d)
    index = N.index(network, class)
    i = N.to_index(index, l)
    check_with_ref(d, value, m, l, i)
end

#-------------------------------------------------------------------------------------------
# Late-check: input has just been checked and parsed into the meaningful data received.
# All brought blueprint have been expanded,
# so input may now be checked against the general model value.

function late_check_vec(d::Dispatcher, m::Model, vec::Vector)
    net = F.value(m)
    class = D.class(d)
    index = N.index(net, class)
    names = N.labels(index)
    try
        for (name, (i, value)) in zip(names, enumerate(vec))
            check_with_ref(d)
        end
    catch e
        e isa InputError || rethrow(e)
        inerr("When checking $d values array against model:\n$(e.message)", rethrow)
    end
    vec
end

#-------------------------------------------------------------------------------------------
# Mutation: called when setting through a view. Input may be anything,
# but the underlying value can be assumed to be correct.

mutate_check(d::Dispatcher, T::Type, m::Model, value, ref) =
    try
        value = check_with_ref(d, T, value, ref)
        check_with_ref(d, m, value, ref)
    catch e
        e isa InputError || rethrow(e)
        inerr("When attempting to mutate $d node value:\n$(e.message)", rethrow)
    end

# ==========================================================================================
# Convenience ready-to-use typical specialization for `from_value`.

# Non-negative values required.
function non_negative(T, input)
    v = inputconvert(T, input)
    v < 0 && inerr("Value cannot be negative. Received: $(repr(input))")
    v
end
