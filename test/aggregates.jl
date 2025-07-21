module TestAggregates

using Main
using EcologicalNetworksDynamics.Aggregates
using Test

@testset "Basic aggregate use." begin

    x = Aggregate()
    add_field!(x, :a, 5)
    add_field!(x, :b, 8)
    add_field!(x, :v, Int[1, 2, 3])

    @test is_disp(x, strip("""
        Aggregate:
          a: 5
          b: 8
          v: [1, 2, 3]
        """))

    # Read.
    @test scan(x.v, sum) == 6

    # Reassign.
    x.a = 8
    x.b = 13

    # Mutate.
    x.v[2] *= 10

    @test is_disp(x, strip("""
        Aggregate:
          a: 8
          b: 13
          v: [1, 20, 3]
        """))

    # Fork.
    y = copy(x)

    # This only increases fields counts..
    either = strip("""
       Aggregate:
         a<2>: 8
         b<2>: 13
         v<2>: [1, 20, 3]
       """)
    @test is_disp(x, either) && is_disp(y, either)

    # .. and is underlying aliasing..
    field(v) = Aggregates.entry(v).field # /!\ Private. Only used here for testing.
    @test field(y.a) === field(x.a)
    @test field(y.b) === field(x.b)
    @test field(y.v) === field(x.v)
    @test field(y.v).value === field(x.v).value

    # .. until mutation.
    y.a *= 10
    mutate!(x.v, push!, 100)

    @test is_disp(x, strip("""
        Aggregate:
          a: 8
          b<2>: 13
          v: [1, 20, 3, 100]
        """))
    @test is_disp(y, strip("""
        Aggregate:
          a: 80
          b<2>: 13
          v: [1, 20, 3]
        """))

    @test !(field(y.a) === field(x.a))
    @test field(y.b) === field(x.b)
    @test !(field(y.v) === field(x.v))
    @test !(field(y.v).value === field(x.v).value)

end

@testset "Aggregate views aliasing." begin

    x = Aggregate()
    add_field!(x, :a, Int[])

    # Two views, same value.
    u = x.a
    v = x.a
    @test is_repr(u, "View($Int[])")
    @test is_repr(v, "View($Int[])")

    # Mutate through one, see through the other.
    mutate!(u, push!, 5)
    @test is_repr(u, "View([5])")
    @test is_repr(v, "View([5])")

    # Reassign, see through either.
    x.a = [8]
    @test is_repr(u, "View([8])")
    @test is_repr(v, "View([8])")

    # Edit field from numerous views.
    add_field!(x, :b, Char[])
    for letter in 'a':'z'
        mutate!(x.b, push!, letter)
    end
    @test x.b == collect('a':'z')

    # Edit field in multiple copies.
    add_field!(x, :c, [])
    for _ in 1:10
        y = copy(x)
        mutate!(y.c, push!, 1)
        @test y.c == [1]
    end
    @test scan(x.c, isempty) # Unchanged.

    # Same, but every copy forks from the previous one.
    previous = [x]
    for i in 1:10
        y = copy(first(previous))
        mutate!(y.c, push!, 1)
        @test y.c == repeat([1], i) # Each time longer.
        previous[1] = y
    end
    @test scan(x.c, isempty) # Still unchanged.

    # Clears temporary views/aggregates just fine.
    GC.gc()

end

end
