"""
Testing utils.
Not useful for end users, but heavily used in package automated testing
and useful to setup development environment with Revise for contributors.
"""
module Tests

include("./strings.jl")
include("./errors.jl")

#-------------------------------------------------------------------------------------------
# Exposed testing interface.

const T = Tests

using EcologicalNetworksDynamics: EN, SparseMatrix

using .Strings:
    is_string, is_repr, is_disp,
    check_string, check_repr, check_disp, check_err,
    @test_string, @test_repr, @test_disp, @test_err
using .Errors: @fails, @fails_with, @genfailsmacro, FieldsCompare

# The collection of macros directly used in tests.
@genfailsmacro deffails UndefVarError (; world = nothing)
@genfailsmacro netfails EN.Networks.NetworkError
@genfailsmacro labelfails EN.Networks.LabelError (; index = nothing)

# (reassure JuliaLS)
macro deffails end
macro netfails end
macro labelfails end

end
