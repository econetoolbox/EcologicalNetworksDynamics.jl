@testset "Temperature component." begin

    # Nothing much specific to test about temperature.

    # Default value.
    bp = Temperature()
    @test bp == Temperature.Raw(293.15)

end
