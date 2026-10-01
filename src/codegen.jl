"""
Construct the name expression required to add a method to the given item.

```
Module.A => :(\$Module.\$(:A))
fn       => :(::\$(typeof(fn)))
```
"""
function methlhs(T::Type)
    n = T.name
    :($(n.module).$(n.name))
end
methlhs(U::UnionAll) = methlhs(U.body)
methlhs(fn::Function) = :(::$(typeof(fn)))

"`:((esc(a), esc(b))) != (:(esc(a)), :(esc(b)))` so esc.((a, b)) won't do."
escall(xp::Tuple) = Expr(:tuple, esc.(xp)...)

# ==========================================================================================
# Paths.

"""
Check whether the expression is a `raw.identifier.path`.
(Useful for properties accesses.)
"""
function is_identifier_path(xp)
    xp isa Symbol && return true
    if xp isa Expr
        xp.head == :. || return false
        path, last = xp.args
        last isa QuoteNode || return false
        is_identifier_path(path) && is_identifier_path(last.value)
    else
        false
    end
end

"""
Collect path the 'forward' way: :(a.b.c.d) -> [:a, :b, :c, :d].
(assuming it has been checked by the above function)
"""
function collect_path(path; res = Symbol[])
    if path isa Symbol
        push!(res, path)
    else
        prefix, last = path.args
        collect_path(prefix; res)
        collect_path(last.value; res)
    end
    res
end

"Again, assuming the expression has been checked for being a path."
function last_in_path(path)
    path isa Symbol && return path
    path.args[2].value
end

"Turn collected paths back into paths."
function to_path(v::Vector{Symbol})
    length(v) == 1 && return first(v)
    a..., b = v
    :($(to_path(a)).$b)
end

"Paste two paths together left-to-right."
function paste_paths(a, b)
    v, w = collect_path.((a, b))
    append!(v, w)
    to_path(v)
end
