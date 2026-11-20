# Specialize display for Model = System{Network}.

CS.short(io::IO, ::Type{Model}) = print(io, "Model")

Base.show(io::IO, ::MIME"text/plain", ::Type{Model}) =
    print(io, "$(green)Model$reset $(black)(alias for $(CS.System){$Network})$reset")

# Filter out _-prefixed names.
Base.show(io::IO, ::MIME"text/plain", p::CS.PropertySpace) =
    CS.display_long(io, p, non_underscore)

function CS.bpdisplay(io::IO, BP::Type{<:Blueprint}; color = false)
    (cc, bc, res) = color ? (CS.component_color, CS.blueprint_color, reset) : ("", "", "")
    CP = SL.component(selector(BP)) # TODO: will fail on selectors without components.
    CP = CS.compdisplay(CP)
    BP = BP.name.name
    print(io, "$cc$CP$res.$bc$BP$res")
end

# Strip paths to identifiers up to package root.
function CS.compdisplay(io::IO, CP::Type{<:Component}; color = false)
    s, e = color ? (CS.component_color, reset) : ("", "")
    mod = CP.name.module
    CP = CS.compname(CP)
    path = ["$s$CP$e"]
    while mod !== EN
        push!(path, String(nameof(mod)))
        parent = parentmodule(mod)
        mod = parent
    end
    print(io, join(reverse(path), '.'))
end
# Strip lib-standard leading underscore.
CS.compname(CP::Type{<:Component}) = '<' * lstrip("$(CP.name.name)", '_') * '>'
CS.compname(cp::Component) = lstrip("$(typeof(cp).name.name)", '_')

#-------------------------------------------------------------------------------------------
# Default display for blueprint fields.

# Vector.
function CS.display_blueprint_field_short(io::IO, v::AbstractVector, ::Blueprint)
    print(io, "[$(join_elided(v, ", "))]")
end

# Matrix.
function CS.display_blueprint_field_short(io::IO, m::AbstractMatrix, ::Blueprint)
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
function CS.display_blueprint_field_short(io::IO, m::EN.SparseMatrix, ::Blueprint)
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

function CS.display_blueprint_field_long(io::IO, m::EN.SparseMatrix, ::Blueprint)
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
function CS.display_blueprint_field_short(io::IO, map::Map, ::Blueprint)
    it = I.map(map) do (k, v)
        "$k: $v"
    end
    print(io, "{$(join_elided(it, ", "; repr = false))}")
end

# Adjacency list.
function CS.display_blueprint_field_short(io::IO, adj::Adjacency, bp::Blueprint)
    it = I.map(adj) do (k, v)
        "$k: $(sprint(CS.display_blueprint_field_short, v, bp))"
    end
    print(io, "{$(join_elided(it, ", "; repr = false))}")
end

# Binary map.
function CS.display_blueprint_field_short(io::IO, set::BinMap, ::Blueprint)
    print(io, "{$(join_elided(set, ", "; repr = false))}")
end

# Binary adjacency list.
function CS.display_blueprint_field_short(io::IO, adj::BinAdjacency, bp::Blueprint)
    it = I.map(adj) do (k, v)
        "$k: $(sprint(CS.display_blueprint_field_short, v, bp))"
    end
    print(io, "{$(join_elided(it, ", "; repr = false))}")
end

# Defer long to short by default.
CS.display_blueprint_field_long(io::IO, v, bp::Blueprint) =
    CS.display_blueprint_field_short(io, v, bp)
