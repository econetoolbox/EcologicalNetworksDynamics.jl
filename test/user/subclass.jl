"""
Test all aspects of typical Subclass component, using producers as an example.
"""
module SubclassTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.NetworkFramework: D, Views
using EcologicalNetworksDynamics.Tests: @viewfails, @immutfails, @test_repr, @test_disp
using OrderedCollections
using SparseArrays
using Test

const d, _D = D.Subclass(:producers, :species)
const View = Views.NodeMaskView{d} # Tested view type.

@testset "Subclass component: properties & views" begin

    m = Model(Foodweb([:a => (:b, :c), :d => :e]))

    # Properties are restricted within the parent component.
    @test m.producers.names == [:b, :c, :e]
    @test m.producers.number == 3
    @test m.producers.index == OrderedDict(:b => 1, :c => 2, :e => 3)
    @test m.producers.parent_index == OrderedDict(:b => 2, :c => 3, :e => 5)

    v = m.producers.mask
    @test v isa AbstractArray{Bool}
    @test v isa View

    e = extract(v)
    @test e isa SparseVector{Bool}
    @test e == v == [0, 1, 1, 0, 1]

    @test v[1] == v[:a] == false # Not a producer.
    @test v[2] == v[:b] == true # Is a producer.
    @test v == [v[i] for i in eachindex(v)] == [v[s] for s in m.species.names] ==
          [0, 1, 1, 0, 1]

    # Also accepts diverse index input.
    @test v[0x1] == v['a'] == false
    @test v[end] == v[end - 2] == true
    @test v[Bool[0, 1, 0, 1, 0]] == [1, 0]

    # Same guards as node names views.
    @viewfails(v[], View, "Node-level data has 1 dimension, received 0")
    @viewfails(v[1, 2], View, "Node-level data has 1 dimension, received 2")
    @viewfails(v[true], View, "Views are queried with indices [::Int] or labels [::Symbol]")
    @viewfails(v[(1,)], View, "Cannot index into views with explicit tuples")
    @viewfails(v[0x8000000000000000], View,
        "Index too large to be used with julia arrays (9223372036854775808)")
    @viewfails(v[-5], View, "Integer node references can only be positive")
    @viewfails(v[[0, 1, 2]], View,
        "Could not interpret as a boolean mask (not only 1's and 0's?)")
    @viewfails(v[6], View, "The parent class only contains 5 nodes")
    @viewfails(v[:x], View, "No node in the parent class is labeled :x")
    @viewfails(v[end+1], View, "The parent class only contains 5 nodes")
    @viewfails(v[(end-1):(end+1)], View, "The parent class only contains 5 nodes")
    @viewfails(v[[0, 1]], View,
        "The given mask is of size 2 but there are 5 nodes in the class")
    @immutfails((v[1] = :u), View)
    @immutfails((v[:a] = :u), View)
    @immutfails((v[:a] = 2), View)
    @immutfails((v[] = 2), View)
    @immutfails((v[1, 2] = 2), View)
    @immutfails((v[nothing] = 2), View)

    @test_repr(v, "<species:producers>[·, 1, 1, ·, 1]")
    @test_disp(v,
        """
        NodeMaskView<species:producers>{Bool} (3/5 values)
         ·
         1
         1
         ·
         1\
        """)
end

@testset "Degenerate self-parent mask" begin

    # Mask within the parent class (no parent class with this root example).
    m = Model(Species("abc"))
    k = m.species.mask
    @test k == [1, 1, 1]
    @test k[1] && k[2] && k[3]
    @test k[:a] && k[:b] && k[:c]
    @test k == Bool[1, 1, 1]
    @test k[1:2] == Bool[1, 1]
    @test k[(end-1):end] == Bool[1, 1]
    @test_repr(k, "<·:species>[1, 1, 1]")
    @test_disp(k,
        """
        NodeMaskView<·:species>{Bool} (3/3 values)
         1
         1
         1\
        """)

end

end
