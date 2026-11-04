# A collection of small utils shared throughout the project.

const Option{T} = Union{T,Nothing}
const SparseMatrix{T} = SparseMatrixCSC{T,Int}

#-------------------------------------------------------------------------------------------
"Filter + map over iterator. The last argument explains which values to filter out."
filter_map(f, it, filter = !isnothing) = I.map(something, I.filter(filter, I.map(f, it)))

#-------------------------------------------------------------------------------------------
"Adapt iterator to stop yielding when the given condition is met."
stopwhen(cond, it) = StopWhen(it, cond)

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

#-------------------------------------------------------------------------------------------
"Zip iterators, filling up the shortests with padding until the longest is over."
zip_longest(its...; pad = nothing) = stopwhen(
    zip(I.map(its) do it
        I.flatten((it, I.repeated(pad)))
    end...)) do values
    all(values .== pad)
end
