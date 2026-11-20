# Fork by adding components with the + operator.
function Base.:+(s::System{V}, bp::Blueprint{V}) where {V}
    clone = copy(s)
    add!(clone, bp)
    clone
end

# To allow constructs like `system += blueprint + blueprint`,
# we need to provide a meaning to `blueprint + blueprint`.
# (just an ordered pack of blueprints waiting to be eventually added to a system value)
struct BlueprintSum{V}
    pack::Vector{<:Blueprint{V}}
    BlueprintSum{V}(p) where {V} = new{V}(p)
    BlueprintSum{V}() where {V} = new{V}(Blueprint{V}[])
end
Base.:+(a::Blueprint{V}, bp::Blueprint{V}) where {V} = BlueprintSum{V}([a, bp])
Base.:+(sum::BlueprintSum{V}, bp::Blueprint{V}) where {V} =
    BlueprintSum{V}(vcat(sum.pack, [bp]))
Base.:+(bp::Blueprint{V}, sum::BlueprintSum{V}) where {V} =
    BlueprintSum{V}(vcat([bp], sum.pack))
Base.:+(a::BlueprintSum{V}, bp::BlueprintSum{V}) where {V} =
    BlueprintSum{V}(vcat(a.pack, bp.pack))
function Base.:+(s::System{V}, sum::BlueprintSum{V}) where {V}
    clone = copy(s)
    add!(clone, sum.pack...)
    clone
end

function Base.show(io::IO, sum::BlueprintSum)
    print(io, "(")
    print(io, join(sum.pack, " + "))
    print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", sum::BlueprintSum)
    print(io, "   $(first(sum.pack))")
    for bp in sum.pack[2:end]
        print(io, "\n + $bp")
    end
end
