import .Iterators as I

# Useful addition to iterators provided the closure returns Union{Some,Nothing}.
filter_map(f, v) = I.map(something, I.filter(!isnothing, I.map(f, v)))

# Iterator adapter that stops yielding when the given condition is met.
struct StopWhen{I,F}
    inner::I
    condition::F
end
function Base.iterate(s::StopWhen, args...)
    next = iterate(s.inner, args...)
    isnothing(next) && return nothing
    (item, state) = next
    s.condition(item) && return nothing
    (item, state)
end
Base.IteratorSize(::StopWhen) = Base.SizeUnknown()
Base.IteratorEltype(s::StopWhen) = Base.IteratorEltype(s.inner)
Base.eltype(s::StopWhen) = Base.eltype(s.inner)
Base.isdone(s::StopWhen, args...) = Base.isdone(s.inner, args...)
stopwhen(cond, it) = StopWhen(it, cond)
