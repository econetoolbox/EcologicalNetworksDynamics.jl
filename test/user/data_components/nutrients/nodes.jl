@testset "Nutrients nodes component." begin

    # At its core, a raw, autonomous compartment.
    n = Nutrients.Nodes(3)
    m = Model(n)
    @test m.n_nutrients == m.nutrients_richness == 3
    @test m.nutrients_names == [:n1, :n2, :n3]

    # Get a closure to convert index to label.
    lab = m.nutrient_label
    @test lab(1) == :n1
    @test lab.([1, 2, 3]) == [:n1, :n2, :n3]

    m = Model(Nutrients.Nodes([:a, :b, :c]))
    @test m.nutrients_index == OrderedDict(:a => 1, :b => 2, :c => 3)

    @sysfails(
        Model(Nutrients.Nodes([:a, :b, :a])),
        Check(Nutrients.RawNodes),
        "Nutrients 1 and 3 are both named :a."
    )

    @argfails(
        Model(Nutrients.Nodes(2)).nutrient_label(3),
        "Invalid index (3) when there are 2 nutrients names."
    )

    # But blueprints exist to construct it from a foodweb.
    n = Nutrients.Nodes(:one_per_producer)
    m = Model(Foodweb([:a => :b, :c => :d])) + n
    @test m.n_nutrients == 2
    @test m.nutrients_names == [:n1, :n2]

    @sysfails(
        Model(n),
        Check(Nutrients.NodesFromFoodweb),
        "missing required component '$Foodweb'.",
    )

end
