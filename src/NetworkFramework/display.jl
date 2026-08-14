# Specialize display for Model = System{Network}.

Base.show(io::IO, ::Type{Model}) = print(io, "Model")

Base.show(io::IO, ::MIME"text/plain", I::Type{Network}) = Base.show(io, I)
Base.show(io::IO, ::MIME"text/plain", ::Type{Model}) =
    print(io, "$(green)Model$reset $(black)(alias for $(F.System){$Network})$reset")

# Filter out _-prefixed names.
Base.show(io::IO, p::F.PropertySpace{name,P,Network}) where {name,P} =
    F.display_long(io, p, non_underscore)

function F.bpdisplay(io::IO, B::Type{<:Blueprint}; color = false)
    (cc, bc, res) = color ? (F.component_color, F.blueprint_color, reset) : ("", "", "")
    C = D.component(dispatcher(B)) # TODO: will fail on dispatchers without components.
    C = F.compdisplay(C)
    B = B.name.name
    print(io, "$cc$C$res.$bc$B$res")
end

# Strip paths to identifiers up to package root.
function F.compdisplay(io::IO, C::Type{<:Component}; color = false)
    s, e = color ? (F.component_color, reset) : ("", "")
    mod = C.name.module
    C = F.compname(C)
    path = ["$s$C$e"]
    while mod !== EN
        push!(path, nameof(mod))
        parent = parentmodule(mod)
        mod = parent
    end
    print(io, join(reverse(path), '.'))
end
# Strip lib-standard leading underscore.
F.compname(C::Type{<:Component}) = '<' * lstrip("$(C.name.name)", '_') * '>'
F.compname(c::Component) = lstrip("$(typeof(c).name.name)", '_')

#-------------------------------------------------------------------------------------------
# Default display for blueprint fields.

# Vector.
function F.display_blueprint_field_short(io::IO, v::AbstractVector, ::Blueprint)
    print(io, "[$(EN.join_elided(v, ", "))]")
end

# Matrix.
function F.display_blueprint_field_short(io::IO, m::AbstractMatrix, ::Blueprint)
    (p, q) = size(m)
    print(io, "$p×$q matrix (")
    min, max = extrema(m)
    if min == max
        print(io, "$min")
    else
        print(io, "$min to $max")
    end
    print(io, ")")
end

# Sparse matrix.
function F.display_blueprint_field_short(io::IO, m::EN.SparseMatrix, ::Blueprint)
    (p, q) = size(m)
    _, _, values = EN.findnz(m)
    n = length(values)
    print(io, "$p×$q:$n")
    if n > 0
        min, max = extrema(values)
        if min == max
            print(io, " ($(first(values)))")
        else
            print(io, " [$min:$max]")
        end
    end
end

function F.display_blueprint_field_long(io::IO, m::EN.SparseMatrix, ::Blueprint)
    (p, q) = size(m)
    print(io, "$p×$q ")
    _, _, values = EN.findnz(m)
    n = length(values)
    if n == 0
        print(io, "empty sparse matrix")
    else
        print(io, "sparse matrix with $n values (")
        min, max = extrema(values)
        if min == max
            print(io, "$min")
        else
            print(io, "$min to $max")
        end
        print(io, ")")
    end
end

# Map.
function F.display_blueprint_field_short(io::IO, map::Map, ::Blueprint)
    it = I.map(map) do (k, v)
        "$k: $v"
    end
    print(io, "{$(EN.join_elided(it, ", "; repr = false))}")
end

# Adjacency list.
function F.display_blueprint_field_short(io::IO, adj::Adjacency, bp::Blueprint)
    it = I.map(adj) do (k, v)
        "$k: $(sprint(F.display_blueprint_field_short, v, bp))"
    end
    print(io, "{$(EN.join_elided(it, ", "; repr = false))}")
end

# Binary map.
function F.display_blueprint_field_short(io::IO, set::BinMap, ::Blueprint)
    print(io, "{$(EN.join_elided(set, ", "; repr = false))}")
end

# Binary adjacency list.
function F.display_blueprint_field_short(io::IO, adj::BinAdjacency, bp::Blueprint)
    it = I.map(adj) do (k, v)
        "$k: $(sprint(F.display_blueprint_field_short, v, bp))"
    end
    print(io, "{$(EN.join_elided(it, ", "; repr = false))}")
end

# Defer long to short by default.
F.display_blueprint_field_long(io::IO, v, bp::Blueprint) =
    F.display_blueprint_field_short(io, v, bp)
