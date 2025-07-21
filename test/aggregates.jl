module TestAggregates

using Main
using EcologicalNetworksDynamics.Aggregates
using Test

@testset "Basic aggregate use." begin

    x = Aggregate()
    add_field!(x, :a, 5)
    add_field!(x, :b, 8)
    add_field!(x, :v, Int[1, 2, 3])

    @test is_repr(x, strip("""
        Aggregate:
          a[1]: 5
          b[1]: 8
          v[1]: [1, 2, 3]
        """))

    # Read.
    @test scan(x.v, sum) == 6

    # Reassign.
    x.a = 8
    x.b = 13

    # Mutate.
    x.v[2] *= 10

    @test is_repr(x, strip("""
        Aggregate:
          a[1]: 8
          b[1]: 13
          v[1]: [1, 20, 3]
        """))

    # Fork.
    y = copy(x)

    # This only increases fields counts..
    either = strip("""
       Aggregate:
         a[2]: 8
         b[2]: 13
         v[2]: [1, 20, 3]
       """)
    @test is_repr(x, either) && is_repr(y, either)

    # .. and is underlying aliasing..
    field(v) = Aggregates.entry(v).field # /!\ Private. Only used here for testing.
    @test field(y.a) === field(x.a)
    @test field(y.b) === field(x.b)
    @test field(y.v) === field(x.v)
    @test field(y.v).value === field(x.v).value

    # .. until mutation.
    y.a *= 10
    mutate!(x.v, push!, 100)

    @test is_repr(x, strip("""
        Aggregate:
          a[1]: 8
          b[2]: 13
          v[1]: [1, 20, 3, 100]
        """))
    @test is_repr(y, strip("""
        Aggregate:
          a[1]: 80
          b[2]: 13
          v[1]: [1, 20, 3]
        """))

    @test !(field(y.a) === field(x.a))
    @test field(y.b) === field(x.b)
    @test !(field(y.v) === field(x.v))
    @test !(field(y.v).value === field(x.v).value)

end

end
