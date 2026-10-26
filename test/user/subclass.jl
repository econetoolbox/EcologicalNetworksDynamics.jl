"Test all aspects of typical Subclass component, using producers as an example."
module SubclassTest

using EcologicalNetworksDynamics

using EcologicalNetworksDynamics.NetworkFramework: D, Views
using EcologicalNetworksDynamics.Tests:
    @test_err, @viewfails, @immutfails, @test_repr, @test_disp
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
    @test v[end] == v[end-2] == true
    @test v[Bool[0, 1, 0, 1, 0]] == [1, 0]
    @test v[[2, 4]] == [1, 0]
    @test v[['b', 'd']] == [1, 0]

    # Same guards as node names views.
    @test v isa AbstractSparseVector{Bool}
    @test_err(v[], "BoundsError: attempt to access 5-element $View at index []")
    @test_err(v[1, 2], "BoundsError: attempt to access 5-element $View at index [1, 2]")
    @test_err(v[true], "ArgumentError: invalid index: true of type Bool")
    @test_err(v[(3,)], "ArgumentError: invalid index: (3,) of type Tuple{$Int}")
    @test_err(v[0x8000000000000000], "InexactError: convert(Int64, 0x8000000000000000)")
    @test_err(v[(end-1):(end+1)],
        "BoundsError: attempt to access 5-element $View at index [4:6]")
    @test_err(v[Bool[0, 1]],
        "BoundsError: attempt to access 5-element $View at index [2-element Vector{Bool}]")

    @viewfails(v[-5],
        (d, -5, (1,), nothing, "Integer node references can only be positive."))
    @viewfails(v[6], (d, 6, (1,), nothing, "The parent class only contains 5 nodes."))
    @viewfails(v[:x], (d, :x, (1,), nothing, "No node in the parent class is labeled :x."))
    @viewfails(v[end+1], (d, 6, (1,), nothing, "The parent class only contains 5 nodes."))

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
