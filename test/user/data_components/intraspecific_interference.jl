@testset "Intra-specific interference component." begin

    # Mostly duplicated from HalfSaturationDensity.

    base = Model(Foodweb([:a => :b, :b => :c]))

    #---------------------------------------------------------------------------------------
    # From raw values.

    # Map selected species.
    for map in ([:a => 1, :b => 2], [1 => 1, 2 => 2])
        ii = IntraspecificInterference(map)
        m = base + ii
        @test m.intraspecific_interference == [1, 2, 0]
        @test typeof(ii) == IntraspecificInterference.Map
    end

    # From a sparse vector.
    ii = IntraspecificInterference([2, 4, 0])
    m = base + ii
    @test m.intraspecific_interference == [2, 4, 0]
    @test typeof(ii) == IntraspecificInterference.Raw

    # From a single value.
    ii = IntraspecificInterference(2)
    m = base + ii
    @test m.intraspecific_interference == [2, 2, 0]
    @test typeof(ii) == IntraspecificInterference.Flat

    # ======================================================================================
    # Guards.

    #---------------------------------------------------------------------------------------
    # Raw values.

    @sysfails(
        base + IntraspecificInterference([:c => 1]),
        Check(
            late,
            [IntraspecificInterference.Map],
            "Invalid 'consumer' node label in 'c': [:c] (1.0). \
             Valid nodes labels for this template are:\n  [:a, :b]",
        )
    )

    @sysfails(
        base + IntraspecificInterference([4, 5, 7]),
        Check(
            late,
            [IntraspecificInterference.Raw],
            "Non-missing value found for 'c' at node index [3] (7.0), \
             but the template for 'consumers' only allows values \
             at the following indices:\n  [1, 2]",
        )
    )

    @sysfails(
        base + IntraspecificInterference([0, -1, +1]),
        Check(early, [IntraspecificInterference.Raw], "Not a positive value: c[2] = -1.0.")
    )

    @sysfails(
        base + IntraspecificInterference(-1),
        Check(early, [IntraspecificInterference.Flat], "Not a positive value: c = -1.0.")
    )

    @sysfails(
        base + IntraspecificInterference([:a => 0, :b => -1, :c => 1]),
        Check(
            early,
            [IntraspecificInterference.Map],
            "Not a positive value: c[:b] = -1.0.",
        )
    )

    # ======================================================================================
    # Edit guards.

    @viewfails(
        (m.intraspecific_interference[3] = 2),
        EN.IntraspecificInterferences,
        "Invalid consumer index [3] to write node data. \
         Valid indices for this template are 1 and 2.",
    )

    @failswith(
        (m.intraspecific_interference[1] = -2),
        WriteError(
            "Not a positive value: c[1] = -2.",
            :intraspecific_interference,
            (1,),
            -2,
        ),
    )

end
