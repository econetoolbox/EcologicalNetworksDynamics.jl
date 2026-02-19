# Checking utils: verify input values either:
#   - isolated (with component extension points)
#   - referenced within a class / web with a context access like (i,) or (i, j).
#   - accompanied with a full model value.

# Non-negative values required.
function non_negative(T, input)
    v = absorb(T, input)
    v < 0 && inerr("Value cannot be negative")
    v
end

# HERE: collect after cleanup as the need arises.
