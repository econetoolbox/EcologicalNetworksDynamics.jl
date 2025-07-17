module TestNutrientNodes
using Test
using EcologicalNetworksDynamics
using Main.TestFailures
using Main.TestUser

@testset "Nutrients nodes component." begin

    # Mostly duplicated from Species.

    base = Model()

    # From names.
    nt = Nutrients.Nodes([:a, :b, :c])
    m = base + nt
    @test m.nutrients.number == m.nutrients.richness == 3
    @test m.nutrients.index == Dict(:a => 1, :b => 2, :c => 3)
    @test m.nutrients.names == [:a, :b, :c]
    @test typeof(nt) == Nutrients.Nodes.Names

    # Get a closure to convert index to label.
    lab = m.nutrients.label
    @test lab(1) == :a
    @test lab.([1, 2, 3]) == [:a, :b, :c]

    # From a number of species (default names generated).
    nt = Nutrients.Nodes(3)
    m = base + nt
    @test m.nutrients.names == [:n1, :n2, :n3]
    @test typeof(nt) == Nutrients.Nodes.Number

    # From the foodweb.
    n = Nutrients.Nodes()
    m = Model(Foodweb([:a => :b, :c => :d])) + n
    @test m.nutrients.number == 2
    @test m.nutrients.names == [:n1, :n2]
    m = Model(Foodweb([:a => :b, :c => :d]), Nutrients.Nodes.PerProducer(3))
    @test m.nutrients.number == 6

    @sysfails(Model(n), Missing(Foodweb, nothing, [Nutrients.Nodes.PerProducer], nothing))

    #---------------------------------------------------------------------------------------
    # Guards.

    @argfails(
        Species(Dict([:a => 1, :c => 3])),
        "Invalid index: received 2 references but one of them is [3] (:c)."
    )

    @argfails(
        Species(Dict([:a => 1, :c => 1])),
        "Invalid index: no reference given for index [2]."
    )

    @sysfails(
        Model(Nutrients.Nodes([:a, :b, :a])),
        Check(early, [Nutrients.Nodes.Names], "Nutrients 1 and 3 are both named :a."),
    )

    @argfails(
        Model(Nutrients.Nodes([:a, :b])).nutrients.label(3),
        "Invalid index (3) when there are 2 nutrient names."
    )

end

end
