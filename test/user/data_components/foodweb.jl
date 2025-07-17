module TestFoodweb
using Test
using EcologicalNetworksDynamics
using Main.TestFailures
using Main.TestUser

@testset "Foodweb component." begin
    # Very structuring, the foodweb does provide a lot of properties.

    base = Model()

    #---------------------------------------------------------------------------------------
    # From a matrix

    fw = Foodweb([
        0 1 1
        0 0 1
        0 0 0
    ])
    m = base + fw
    # Species component is automatically brought.
    @test m.S == 3
    @test m.species.names == [:s1, :s2, :s3]
    @test typeof(fw) == Foodweb.Matrix

    #---------------------------------------------------------------------------------------
    # From an adjacency list.

    # Integer keys.
    fw = Foodweb([2 => 3, 1 => [3, 2]])
    m = base + fw
    @test m.S == 3
    @test m.species.names == [:s1, :s2, :s3]
    @test typeof(fw) == Foodweb.Adjacency

    # Symbol keys.
    fw = Foodweb([:a => [:b, :c], :b => :c])
    m = base + fw
    @test m.S == 3
    @test m.species.names == [:a, :b, :c]
    @test typeof(fw) == Foodweb.Adjacency

    #---------------------------------------------------------------------------------------
    # Properties brought by the foodweb.

    @test m.trophic.matrix == m.A == [
        0 1 1
        0 0 1
        0 0 0
    ]
    @test m.trophic.n_links == 3
    @test m.trophic.levels == [2.5, 2.0, 1.0]

    # Either query with indices or species name.
    @test m.trophic.levels[2] == 2
    @test m.trophic.levels[:b] == 2
    @viewfails(
        m.trophic.levels[:x],
        EN.TrophicLevels,
        "Invalid species node label. \
         Expected either :a, :b or :c, got instead: :x."
    )

    #---------------------------------------------------------------------------------------
    # Producers/consumer data is deduced from the foodweb.

    @test m.producers.mask == Bool[0, 0, 1]
    @test m.consumers.mask == Bool[1, 1, 0]
    @test m.preys.mask == Bool[0, 1, 1]
    @test m.tops.mask == Bool[1, 0, 0]
    @test m.producers.number == 1
    @test m.consumers.number == 2
    @test m.preys.number == 2
    @test m.tops.number == 1

    @test is_consumer(m, 2)
    @test is_consumer(m, :b) # Equivalent.
    @test is_producer(m, :c)
    @test is_prey(m, :b)
    @test is_top(m, :a)

    @test collect(m.producers.indices) == [3]
    @test collect(m.consumers.indices) == [1, 2]
    @test collect(m.preys.indices) == [2, 3]
    @test collect(m.tops.indices) == [1]

    @test m.producers.sparse_index == Dict(:c => 3)
    @test m.producers.dense_index == Dict(:c => 1)
    @test m.consumers.sparse_index == Dict(:a => 1, :b => 2)
    @test m.consumers.dense_index == Dict(:a => 1, :b => 2)
    @test m.preys.sparse_index == Dict(:b => 2, :c => 3)
    @test m.preys.dense_index == Dict(:b => 1, :c => 2)
    @test m.tops.sparse_index == Dict(:a => 1)
    @test m.tops.dense_index == Dict(:a => 1)

    #---------------------------------------------------------------------------------------
    # Higher-level links info.

    m = Model(Foodweb([2 => [1, 3], 4 => [2, 3]]))

    @test m.trophic.matrix == [
        0 0 0 0
        1 0 1 0
        0 0 0 0
        0 1 1 0
    ]

    @test m.producers.matrix == [
        1 0 1 0
        0 0 0 0
        1 0 1 0
        0 0 0 0
    ]

    @test m.trophic.herbivory_matrix == [
        0 0 0 0
        1 0 1 0
        0 0 0 0
        0 0 1 0
    ]

    @test m.trophic.carnivory_matrix == [
        0 0 0 0
        0 0 0 0
        0 0 0 0
        0 1 0 0
    ]

    #---------------------------------------------------------------------------------------]
    # Input guards.

    @sysfails(
        Model(Foodweb([
            0 1 0
            0 0 1
        ])),
        Check(
            early,
            [Foodweb.Matrix],
            "The adjacency matrix of size (3, 2) is not squared.",
        )
    )

    @sysfails(
        Model(Species(2), Foodweb([
            0 1 1
            0 0 1
            0 0 0
        ])),
        Check(
            late,
            [Foodweb.Matrix],
            "Invalid size for parameter 'A': expected (2, 2), got (3, 3).",
        )
    )

    @sysfails(
        Model(Species(2), Foodweb([:a => :b])),
        Check(
            late,
            [Foodweb.Adjacency],
            "Invalid 'species' edge label in 'A'. \
             Expected either :s1 or :s2, got instead: [:a] (true).",
        )
    )

    @sysfails(
        Model(Species(2), Foodweb([1 => 3])),
        Check(
            late,
            [Foodweb.Adjacency],
            "Invalid 'species' edge index in 'A'. \
             Index does not fall within the valid range 1:2: [3] (true).",
        )
    )

    # Input tests on the `Foodweb` constructor itself live in "../01-input.jl".

end

end
