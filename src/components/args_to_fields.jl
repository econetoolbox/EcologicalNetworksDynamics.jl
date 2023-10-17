# Interpret raw input value as arguments to pass to another function.
to_args_kwargs(input) = ((input,), (;))
to_args_kwargs(input::Tuple) = (input, (;))
to_args_kwargs(input::NamedTuple) = ((), input)
to_args_kwargs(input::Tuple{<:Any,NamedTuple}) = ((input[1],), input[2])
to_args_kwargs(input::Tuple{Tuple,NamedTuple}) = input
to_args_kwargs(args...; kwargs...) = (args, kwargs)

# Pass input value to the given function as args/kwargs.
function pass_args_kwargs(f, input)
    args, kwargs = to_args_kwargs(input)
    f(args...; kwargs...)
end
# Special-case BroughtField because it would otherwise
# fall back attempt to convert to its 'Union' field, which is not a constructor.
pass_args_kwargs(BF::Type{<:F.BroughtField}, ::Nothing) = BF(nothing)
pass_args_kwargs(BF::Type{<:F.BroughtField}, C::F.CompType) = BF(C)
pass_args_kwargs(BF::Type{<:F.BroughtField}, C::F.Component) = BF(C)
pass_args_kwargs(BF::Type{<:F.BroughtField}, bp::F.Blueprint) = BF(bp)
function pass_args_kwargs(BF::Type{<:F.BroughtField}, input)
    ak = to_args_kwargs(input)
    convert(BF, ak)
end

# If the 'given function' is a type,
# pass it to the type as constructor arguments,
# unless the input is already of the right type
# and then there is no need to construct more.
function pass_args_kwargs_to_type(type, input)
    res = input isa type
    res ? input : pass_args_kwargs(type, input)
end

# Given a struct type,
# process kwargs input to pass each value, in order,
# to the corresponding argument of the 'new' function if type matches,
# or as arguments to the constructor type of corresponding field.
# Default values are used to fill fields for which no input was provided.
# Override values will be used to fill fields,
# and it is an error to provide input for them.
# The resulting list is meant to be directly passed to the special `new` function.
# Special-case field::Option{F}, which may be missing,
# and whose type Union{Nothing,F} cannot be called as a constructor.
function fields_from_kwargs(T::DataType, kwargs; default = (;), override = (;))
    given(k) = haskey(kwargs, k)
    overriden(k) = haskey(override, k)
    defaulted(k) = haskey(default, k)
    # Construct one value from every field from the given input.
    values = []
    unconsumed = Set(keys(kwargs))
    field_names = fieldnames(T)
    for (name, fieldtype) in zip(field_names, fieldtypes(T))

        (type, is_optional) = if fieldtype isa Union
            if fieldtype.a === Nothing
                (fieldtype.b, true)
            elseif fieldtype.b === Nothing
                (fieldtype.a, true)
            else
                argerr("Cannot pass input to non-constructor union type: $fieldtype.")
            end
        else
            (fieldtype, false)
        end

        if overriden(name)
            input = override[name]
            value = pass_args_kwargs_to_type(type, input)
            given(name) &&
                argerr("Cannot choose value for field $(repr(name)) = $(repr(value)).")

        elseif given(name)
            input = kwargs[name]
            value =
                (is_optional && isnothing(input)) ? nothing :
                pass_args_kwargs_to_type(type, input)
            pop!(unconsumed, name)

        elseif defaulted(name)
            input = default[name]
            value =
                (is_optional && isnothing(input)) ? nothing :
                pass_args_kwargs_to_type(type, input)

        elseif is_optional
            value = nothing

        else
            argerr("Missing input to initialize field $(repr(name)).")
        end

        push!(values, value)
    end
    # Check that no extra input has been given.
    if !isempty(unconsumed)
        k = first(unconsumed)
        v = kwargs[k]
        argerr("Unexpected input: $k = $(repr(v)). \
                Expected $(either(field_names)).")
    end
    # Ready for forwarding to `new`.
    values
end

either(symbols) =
    length(symbols) == 1 ? "$(repr(first(symbols)))" :
    "either " * join(repr.(symbols), ", ", " or ")
