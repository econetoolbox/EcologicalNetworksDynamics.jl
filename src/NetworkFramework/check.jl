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


# ==========================================================================================
# Convenience ready-to-use typical specialization for `from_value`.

# Non-negative values required.
function non_negative(T, input)
    v = inputconvert(T, input)
    v < 0 && inerr("Value cannot be negative. Received: $(repr(input))")
    v
end
