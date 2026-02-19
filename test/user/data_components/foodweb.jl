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

    @test extract(m.A) isa SparseMatrixCSC{Bool}
    @test m.trophic.matrix == m.A == extract(m.A) == [
        0 1 1
        0 0 1
        0 0 0
    ]
    @test m.trophic.n_links == 3
    @test m.trophic.level == [2.5, 2.0, 1.0]

    # Either query with indices or species name.
    @test m.trophic.level[2] == 2
    @test m.trophic.level[:b] == 2
    @labelfails(m.trophic.level[:x], x, species)

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

    @test collect(m.producers.indices) == [3]
    @test collect(m.consumers.indices) == [1, 2]
    @test collect(m.preys.indices) == [2, 3]
    @test collect(m.tops.indices) == [1]

    @test m.producers.index == OrderedDict(:c => 1)
    @test m.consumers.index == OrderedDict(:a => 1, :b => 2)
    @test m.preys.index == OrderedDict(:b => 1, :c => 2)
    @test m.tops.index == OrderedDict(:a => 1)
    @test m.producers.parent_index == OrderedDict(:c => 3)
    @test m.consumers.parent_index == OrderedDict(:a => 1, :b => 2)
    @test m.preys.parent_index == OrderedDict(:b => 2, :c => 3)
    @test m.tops.parent_index == OrderedDict(:a => 1)

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

    @test m.trophic.herbivory.matrix == m.herbivory.matrix == [
        0 0 0 0
        1 0 1 0
        0 0 0 0
        0 0 1 0
    ]

    @test m.trophic.carnivory.matrix == m.carnivory.matrix == [
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
