@testset "Species components." begin

    m = Model(Species([:a, :b, :c]))

    @test m.richness == 3
    @test m.S == 3
    @test m.species_richness == 3
    @test m.n_species == 3
    @test m.species_index == Dict(:a => 1, :b => 2, :c => 3)
    @test m.species_names == [:a, :b, :c]

    # Get a closure to convert index to label.
    lab = m.species_label
    @test lab(1) == :a
    @test lab.([1, 2, 3]) == [:a, :b, :c]

    # Default names.
    @test Species(3).names == [:s1, :s2, :s3]

    @sysfails(
        Model(Species([:a, :b, :a])),
        Check(Species),
        "Species 1 and 3 are both named :a."
    )

    @argfails(
        Model(Species([:a, :b])).species_label(3),
        "Invalid index (3) when there are 2 species names."
    )

    # Cannot query without the component.
    @sysfails(
        Model().richness,
        Property(richness),
        "Component '$Species' is required to read this property."
    )

end
