"""
Testing utils.
Not useful for end users, but heavily used in package automated testing
and useful to setup development environment with Revise for contributors.
"""
module Tests

include("./strings.jl")
include("./errors.jl")

#-------------------------------------------------------------------------------------------
# The collection of macros directly used in tests.

using EcologicalNetworksDynamics: EN

using .Strings:
    is_string, is_repr, is_disp,
    @test_string, @test_repr, @test_disp, @test_err
using .Errors: @fails, @generrortest

@generrortest netfails EN.Networks.NetworkError

end
