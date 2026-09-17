# Convenience wrappers around `mix!`.

# Also forward to views.
Entries = Tuple{Vararg{Entry}}
Views = Tuple{Vararg{View}}
reassign!(v::View, new) = reassign!(entry(v), new)

"""
Transactional read for one entry (see `mix!`).
"""
Base.read(f, e::Entry) = mix!((_, (r,)) -> (f(r), ()), (), (e,), ())
Base.read(f, v::View) = Base.read(f, entry(v))
"""
Transactional read for one entry with additional arguments passed to `f`.
"""
Base.read(e::Entry, f, args...; kwargs...) = read(e -> f(e, args...; kwargs...), e)
Base.read(v::View, f, args...; kwargs...) = read(entry(v), f, args...; kwargs...)

"""
Transactional mutation for one entry (see `mix`!).
"""
mutate!(f!, e::Entry) = mix!(((w,), _) -> (f!(w), ()), (e,), (), ())
mutate!(f!, v::View) = mutate!(f!, entry(v))
"""
Transactional mutation for one entry with additional arguments passed to `f!`.
"""
mutate!(e::Entry, f!, args...; kwargs...) = mutate!(e -> f!(e, args...; kwargs...), e)
mutate!(v::View, f!, args...; kwargs...) = mutate!(entry(v), f!, args...; kwargs...)
export mutate!

"""
Transactional read-only for multiple entries at once.
"""
Base.read(f, e::Entry, more::Entry...) = mix!((_, r) -> (f(r...), ()), (), (e, more...), ())
Base.read(f, v::View, more::View...) = v(f, entry(v), map(entry, more)...)

"""
Transactional mutation for multiple entries at once.
"""
mutate!(f!, e::Entry...) = mix!((w, _) -> (f!(w...), ()), e, (), ())
mutate!(f!, v::View...) = mutate!(f!, map(entry, v)...)

"""
Transactional reassignment for multiple entries at once.
"""
reassign!(e::Entries, values...) = mix!((_, _) -> ((), values), (), (), e)
reassign!(v::Views, values...) = reassign!(map(entry, v), values...)

#-------------------------------------------------------------------------------------------
# Transform any single entry received as a parameter into a tuple,
# eg. for w and a but not r:
#   mix!(f!, w::Entry, r::Entries, a::Entry) = mix!((w,), r, (a,)) do (w,), r, (a,)
#       f!(w, r, a)
#   end

function modify! end
for i in collect(Iterators.product(repeat([(true, false)], 3)...))
    any(i) || continue
    (ew, vw), (er, vr), (ea, va) = (s ? (Entry, View) : (Entries, Views) for s in i)
    w, r, a = (s ? :(($n,)) : n for (s, n) in zip(i, (:w, :r, :a)))
    me(xp) = :($Base.map($N.entry, $xp))
    N.eval(quote
        """
        Elide tuple for singleton entries (see `mix!`). # (on entries)
        """
        mix!(f!, w::$ew, r::$er, a::$ea) = # (on entries)
            mix!($w, $r, $a) do $w, $r, $a
                f!(w, r, a)
            end
        mix!(f!, w::$vw, r::$vr, a::$va) = # (on views)
            mix!(f!, $(me(w)), $(me(r)), $(me(a)))
    end)

    #---------------------------------------------------------------------------------------
    # Add additional convenience when one of the tuples is empty.
    if ew === Entry #  (to not repeat the same definition)
        N.eval(quote
            """
            Transactional `mix!` without "mutated" entries (see `mix!`).
            """
            reassign!(f, r::$vr, a::$va) = reassign!(f, $(me(r)), $(me(a)))
            reassign!(f, r::$er, a::$ea) =
                mix!((), $r, $a) do _, $r
                    f(r)
                end
        end)
    end

    if er === Entry
        N.eval(quote
            """
            Transactional `mix!` without "read-only" entries (see `mix!`).
            """
            modify!(f!, w::$vw, a::$va) = modify!(f!, $(me(w)), $(me(a)))
            modify!(f!, w::$ew, a::$ea) =
                mix!($w, (), $a) do $w, _
                    f!(w)
                end
        end)
    end

    if ea === Entry
        """
        Transactional `mix!` without "reassigned" entries (see `mix!`).
        """
        N.eval(quote
            mix!(f!, w::$vw, r::$vr) = mix!(f!, $(me(w)), $(me(r)))
            mix!(f!, w::$ew, r::$er) =
                mix!($w, $r, ()) do $w, $r
                    (f!(w, r), ())
                end
        end)
    end

end
