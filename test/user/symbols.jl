"Test basic 'universal' (= any network) symbols exposed by the package."
module Symbols

# What the end user should have to import.
using EcologicalNetworksDynamics

# Additional imports only used here for testing purpose.
using EcologicalNetworksDynamics.NetworkFramework: Network
using EcologicalNetworksDynamics.Tests: @test_repr, @test_disp
using Test

@testset "Universal symbols." begin
    # Nothing fancy for these ones (used to be).
    @test_repr(Component, "$Component")
    @test_repr(Blueprint, "$Blueprint")

    # Simplified paths for these ones.
    @test_disp(Component, "Framework.<Component> (component type for $Network)")
    @test_disp(Blueprint, "Blueprint{Network}")
end

end
