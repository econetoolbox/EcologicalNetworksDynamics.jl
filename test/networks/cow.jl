module NetworkCOW

using EcologicalNetworksDynamics.Networks
const N = Networks

using Test
using Main.TestUtils
import Main: @netfails

@testset "Basic network COW." begin

    n = Network()

    @test is_disp(n, strip("""
        Empty network.
        """))

    add_field!(n, :a, 5)
    add_field!(n, :b, 8)
    add_field!(n, :v, Int[1, 2, 3])
    @netfails add_field!(n, :v, nothing) "Network already contains a field :v."

    @test is_disp(n, strip("""
        Network with 3 fields:
          Graph:
            a: 5
            b: 8
            v: [1, 2, 3]
        """))

    # Read.
    v = graph_view(n, :v)
    @test read(v, sum) == 6

    # Reassign.
    reassign!(graph_view(n, :a), 8)
    reassign!(graph_view(n, :b), 13)
    @netfails(
        reassign!(graph_view(n, :a), "a"),
        "Cannot assign to field of type $Int:\n\
         \"a\" ::String"
    )

    # Mutate.
    v[2] *= 10

    @test is_disp(n, strip("""
        Network with 3 fields:
          Graph:
            a: 8
            b: 13
            v: [1, 20, 3]
        """))

    # Fork.
    m = copy(n)

    # This only increases fields counts..
    either = strip("""
      Network with 3 fields:
        Graph:
          a'2: 8
          b'2: 13
          v'2: [1, 20, 3]
      """)
    @test is_disp(n, either) && is_disp(m, either)

    # .. and is underlying aliasing..
    field(v) = N.field(N.entry(v)) # /!\ Private. Only used here for testing.
    na, nb, nv = graph_view.((n,), (:a, :b, :v))
    ma, mb, mv = graph_view.((m,), (:a, :b, :v))
    @test field(ma) === field(na)
    @test field(mb) === field(nb)
    @test field(mv) === field(nv)
    @test N.value(field(mv)) === N.value(field(nv))

    # .. until mutation.
    reassign!(ma, ma * 10) # TODO: have this work as `ma .*= 10` ? Or is it a bad idea?
    mutate!(nv, push!, 100)

    @test is_disp(n, strip("""
        Network with 3 fields:
          Graph:
            a: 8
            b'2: 13
            v: [1, 20, 3, 100]
        """))

    @test is_disp(m, strip("""
        Network with 3 fields:
          Graph:
            a: 80
            b'2: 13
            v: [1, 20, 3]
        """))

    @test !(field(ma) === field(na))
    @test field(mb) === field(nb)
    @test !(field(mv) === field(nv))
    @test !(N.value(field(mv)) === N.value(field(nv)))

    @netfails(graph_view(n, :bok), "There is no data :bok in the network.")

end

@testset "Network views aliasing." begin

    n = Network()
    add_field!(n, :a, Int[])

    # Two views, same value.
    u = graph_view(n, :a)
    v = graph_view(n, :a)
    View = nameof(N.GraphView)
    @test is_repr(u, "$View($Int[])")
    @test is_repr(v, "$View($Int[])")

    # Mutate through one, see through the other.
    mutate!(u, push!, 5)
    @test is_repr(u, "$View([5])")
    @test is_repr(v, "$View([5])")

    # Reassign, see through either.
    reassign!(u, [8])
    @test is_repr(u, "$View([8])")
    @test is_repr(v, "$View([8])")

    # Edit field from numerous views.
    add_field!(n, :b, Char[])
    for letter in 'a':'z'
        nb = graph_view(n, :b)
        mutate!(nb, push!, letter)
    end
    nb = graph_view(n, :b)
    @test nb == collect('a':'z')

    # Edit field in multiple copies.
    add_field!(n, :c, [])
    for _ in 1:10
        m = copy(n)
        mc = graph_view(m, :c)
        mutate!(mc, push!, 1)
        @test mc == [1]
    end
    nc = graph_view(n, :c)
    @test read(nc, isempty) # Unchanged.

    # Same, but every copy forks from the previous one.
    previous = [n]
    for i in 1:10
        m = copy(first(previous))
        mc = graph_view(m, :c)
        mutate!(mc, push!, 1)
        @test mc == repeat([1], i) # Each time longer.
        previous[1] = m
    end
    @test read(nc, isempty) # Still unchanged.

    # Clears temporary views/aggregates just fine.
    GC.gc()

end

end
