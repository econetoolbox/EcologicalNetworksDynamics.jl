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
