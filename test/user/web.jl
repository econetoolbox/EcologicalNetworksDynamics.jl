"Test all aspects of typical Web component, using foodweb as an example."
module WebTest

using EcologicalNetworksDynamics
using SparseArrays

using EcologicalNetworksDynamics.Tests:
    @test_repr, @test_disp, @test_err, @bpfails, @checkfails, addfails, @propfails,
    @viewfails, @immutfails
using EcologicalNetworksDynamics.NetworkFramework:
    EN, D, F, NF, Network, Views, SparseMatrix
using EcologicalNetworksDynamics.Framework: @PropertySpace
using OrderedCollections
using Test

const d, _D = D.Web(:trophic)
const Tr = @PropertySpace(trophic, Network)
const View = Views.EdgeMaskView{d}

@testset "Web component: blueprints" begin

    @test_disp(
        Foodweb,
        """
        Foodweb (component for $Network, expandable from:
          Matrix: boolean matrix of foodweb links,
          Adjacency: adjacency list of foodweb links,
        )\
        """,
    )

    # ======================================================================================
    # From a matrix.

    A = sparse(Bool[
        0 0 1
        1 0 1
        0 0 0
    ])

    #---------------------------------------------------------------------------------------
    # Construct.

    # Various input types.
    bp = Foodweb.Matrix(A)
    @test bp.A isa SparseMatrix{Bool}
    @test bp == Foodweb.Matrix(collect(A))
    @test bp == Foodweb.Matrix(Int.(A))
    @test bp == Foodweb.Matrix(BitMatrix(A))
    # Implicit constructor.
    @test bp == Foodweb(A)
    @test bp == Foodweb(collect(A))
    @test bp == Foodweb(Int.(A))
    @test bp == Foodweb(BitMatrix(A))
    @test bp == Foodweb(sparse(A))
    @test bp == Foodweb(sparse(Int.(A)))
    @test bp == Foodweb(sparse(BitMatrix(A)))
    @test_repr(bp, "<Foodweb>:Matrix(A: 3×3:3 (true))")
    @test_disp(
        bp,
        """
        blueprint for <Foodweb>: Matrix {
          A: 3×3 sparse matrix with 3 values (true),
        }\
        """,
    )

    # Alias.
    input = sparse(A)
    bp = Foodweb(input)
    @test bp.A === input

    @bpfails(Foodweb.Matrix(:a),
        Foodweb.Matrix, :construct,
        (d, :a, :whole, nothing,
            "Cannot convert to `$(NF.SparseMatrix{Bool})`:\n\
             Conversion not implemented."))

    #---------------------------------------------------------------------------------------
    # Intrinsic check.

    @bpfails(Foodweb(zeros(Bool, 2, 3)),
        Foodweb.Matrix, :construct,
        (d, spzeros(Bool, 2, 3), :whole, nothing,
            "The adjacency matrix of size (3, 2) is not squared."))

    #---------------------------------------------------------------------------------------
    # Late check.

    m = Model(Species(3))
    addfails.@check(m + Foodweb(zeros(Bool, 2, 2)), [],
        (Foodweb.Matrix, :late,
            (d, spzeros(Bool, 2, 2), :whole, nothing,
                "There are 3 :species nodes but the provided matrix is of size (2, 2).")))
    @test_err(m + Foodweb(zeros(Bool, 2, 2)), # First time with a :late error.
        """
        Blueprint cannot expand against current system value:
        While verifying blueprint against model:
        In the provided input for <trophic>:
        There are 3 :species nodes but the provided matrix is of size (2, 2).
        Received: sparse(Int64[], Int64[], Bool[], 2, 2)  ::$(SparseMatrix{Bool})
        Not all blueprints have been expanded.
        This means that the system consistency is still guaranteed, \
        but some components have not been added.
        in Foodweb.Matrix\
        """)

    #---------------------------------------------------------------------------------------
    # Expand, implying underlying class.

    m = Model(bp)
    @test has_component(m, Foodweb)
    @test has_component(m, Species)
    @test_disp(m,
        """
        Model (alias for $(F.System){$Network}) with 2 components:
          - Species: 3 (:s1, :s2, :s3)
          - Foodweb: 3 links, 1 producer, 2 consumers, 2 preys, 1 top.\
        """)

    # ======================================================================================
    # From an adjacency list.

    #---------------------------------------------------------------------------------------
    # Construct.

    A = [:a => (:b, :c), (:b, :d) => :e] # Using labels.
    Ai = [6 => (4, 2), (4, 1) => 3] # Using indices (with a different topology).

    bp = Foodweb.Adjacency(A)
    bpi = Foodweb.Adjacency(Ai)
    @test bp.A isa OrderedDict{Symbol,OrderedSet{Symbol}}
    @test bpi.A isa OrderedDict{Int,OrderedSet{Int}}
    @test bp == Foodweb.Adjacency(['a' => ["b", "c"], ['b', :d] => "e"])
    @test bpi == Foodweb.Adjacency(Iterators.map(identity, [6 => [4, 2], ([4, 1], 3)]))
    # Implicit constructor.
    @test bp == Foodweb(A)
    @test bpi == Foodweb(Ai)
    @test bp == Foodweb(['a' => ["b", "c"], ['b', :d] => "e"])
    @test bpi == Foodweb(Iterators.map(identity, [6 => [4, 2], ([4, 1], 3)]))
    @test_repr(bp, "<Foodweb>:Adjacency(A: {a: {b, c}, b: {e}, d: {e}})")
    @test_repr(bpi, "<Foodweb>:Adjacency(A: {6: {4, 2}, 4: {3}, 1: {3}})")
    @test_disp(bp,
        """
        blueprint for <Foodweb>: Adjacency {
          A: {
            a -> { b, c },
            b -> { e },
            d -> { e },
          },
        }\
        """)
    @test_disp(bpi,
        """
        blueprint for <Foodweb>: Adjacency {
          A: {
            6 -> { 4, 2 },
            4 -> { 3 },
            1 -> { 3 },
          },
        }\
        """)

    # Alias.
    for input in (bp.A, bpi.A)
        bp = Foodweb(input)
        @test bp.A === input
    end

    # All list parsing errors are reported here.
    @bpfails(Foodweb.Adjacency(:a),
        Foodweb.Adjacency, :construct,
        (d, :a, :whole, nothing,
            "Input for binary adjacency map needs to be iterable."))
    @test_err(Foodweb.Adjacency(:a), # First test with :list.
        """
        While constructing blueprint Foodweb.Adjacency:
        In the provided input for <trophic>:
        Input for binary adjacency map needs to be iterable.
        Received: :a  ::Symbol\
        """)

    #---------------------------------------------------------------------------------------
    # Late check.

    addfails.@check(Model(Species("axy"), Foodweb(A)), [],
        (Foodweb.Adjacency, :late,
            (d, :b, [1, :right, 1], nothing, "Not a target label among :species.")))
    addfails.@check(Model(Species("xyz"), Foodweb(Ai)), [],
        (Foodweb.Adjacency, :late,
            (d, 6, [1, :left], nothing, "Not a valid source :species index among 3 nodes."),
        ))

    @test_err(Model(Species("axy"), Foodweb(A)), # First time with path-within-list.
        """
        Blueprint cannot expand against current system value:
        While verifying blueprint against model:
        In the provided input at [1][right][1]:
        Not a target label among :species.
        Received: :b  ::Symbol
        Not all blueprints have been expanded.
        This means that the system consistency is still guaranteed, \
        but some components have not been added.
        in Foodweb.Adjacency\
        """)

    #---------------------------------------------------------------------------------------
    # Expand, implying underlying class.

    m = Model(Foodweb(A))
    @test has_component(m, Foodweb)
    @test has_component(m, Species)
    @test m.species.names == [:a, :b, :c, :e, :d]
    # TODO: the ordering obtained above is unexpected: fix.
    # This is because in general `(a, b) => c` gets parsed as `a => c, b => c`
    # thus reverting the order.
    # The fix would be that the parsing should also produce an ordered list of labels
    # but there is nowhere to store that list within the blueprint yet. (Re)Consider?

    m = Model(Foodweb(Ai))
    @test has_component(m, Foodweb)
    @test has_component(m, Species)
    @test m.species.names == [:s1, :s2, :s3, :s4, :s5, :s6]

    # ======================================================================================
    # Generic construct failure.

    input = [1 => 2 0 1]
    @checkfails(Foodweb(input), d, input, :whole, nothing,
        """
        Cannot convert input to either:
          - $(SparseMatrix{Bool})
          - $(EN.BinAdjacency)
        (see attempts down the stacktrace)\
        """)

end

@testset "Web component: properties" begin

    @propfails(Model().trophic.matrix,
        Tr, :matrix, "Component <Foodweb> is required to read this property.")

    m = Model(Species("abcde"), Foodweb([:a => (:b, :c), (:b, :d) => (:c, :e)]))

    # Number of edges in the web.
    @test m.trophic.n_links == m.trophic.n_edges == 6
    # Topology as a matrix.
    @test m.trophic.matrix == m.trophic.mask ==
          [
              0 1 1 0 0
              0 0 1 0 1
              0 0 0 0 0
              0 0 1 0 1
              0 0 0 0 0
          ]

    # Types.
    @test m.trophic.n_links isa Int
    @test m.trophic.n_edges isa Int
    @test m.trophic.matrix isa Views.EdgeMaskView{d}
    @test m.trophic.mask isa Views.EdgeMaskView{d}

    # Edges iterators.
    c = collect
    mc(it) = map(((src, sub),) -> (src, collect(sub)), it)

    # Flat:
    @test c(m.trophic.iter.edges) == c(m.trophic.iter.label.edges) ==
          [(:a, :b), (:a, :c), (:b, :c), (:d, :c), (:b, :e), (:d, :e)]
    #       1         2         3         4         5         6
    # Nested, forward (source-first).
    @test mc(m.trophic.iter.forward) == mc(m.trophic.iter.label.forward) ==
          [
              (:a, [(:b, 1), (:c, 2)]),
              (:b, [(:c, 3), (:e, 5)]),
              (:c, []),
              (:d, [(:c, 4), (:e, 6)]),
              (:e, []),
          ]
    # Nested, backward (target-first).
    @test mc(m.trophic.iter.backward) == mc(m.trophic.iter.label.backward) ==
          [
              (:a, []),
              (:b, [(:a, 1)]),
              (:c, [(:a, 2), (:b, 3), (:d, 4)]),
              (:d, []),
              (:e, [(:b, 5), (:d, 6)]),
          ]
    # Transposed variant.
    @test c(m.trophic.iter.edges_transposed) == c(m.trophic.iter.label.edges_transposed) ==
          [(:a, :b), (:a, :c), (:b, :c), (:b, :e), (:d, :c), (:d, :e)]
    # Skip variants.
    @test mc(m.trophic.iter.forward_skip) == mc(m.trophic.iter.label.forward_skip) ==
          [
              (:a, [(:b, 1), (:c, 2)]),
              (:b, [(:c, 3), (:e, 5)]),
              (:d, [(:c, 4), (:e, 6)]),
          ]
    @test mc(m.trophic.iter.backward_skip) == mc(m.trophic.iter.label.backward_skip) ==
          [
              (:b, [(:a, 1)]),
              (:c, [(:a, 2), (:b, 3), (:d, 4)]),
              (:e, [(:b, 5), (:d, 6)]),
          ]

    # Index versions.                        1       2       3       4       5       6
    @test c(m.trophic.iter.index.edges) == [(1, 2), (1, 3), (2, 3), (4, 3), (2, 5), (4, 5)]
    @test mc(m.trophic.iter.index.forward) == [
        (1, [(2, 1), (3, 2)]),
        (2, [(3, 3), (5, 5)]),
        (3, []),
        (4, [(3, 4), (5, 6)]),
        (5, []),
    ]
    @test mc(m.trophic.iter.index.backward) == [
        (1, []),
        (2, [(1, 1)]),
        (3, [(1, 2), (2, 3), (4, 4)]),
        (4, []),
        (5, [(2, 5), (4, 6)]),
    ]
    @test c(m.trophic.iter.index.edges_transposed) ==
          [(1, 2), (1, 3), (2, 3), (2, 5), (4, 3), (4, 5)]
    @test mc(m.trophic.iter.index.forward_skip) == [
        (1, [(2, 1), (3, 2)]),
        (2, [(3, 3), (5, 5)]),
        (4, [(3, 4), (5, 6)]),
    ]
    @test mc(m.trophic.iter.index.backward_skip) == [
        (2, [(1, 1)]),
        (3, [(1, 2), (2, 3), (4, 4)]),
        (5, [(2, 5), (4, 6)]),
    ]

end

@testset "Web component: mask view" begin

    bp = Foodweb([:a => (:b, :c), (:b, :d) => (:c, :e)])
    m = Model(Species("abcde"), bp)
    v = m.trophic.mask

    @test v isa View
    @test_repr(v, "<trophic>(5×5: 6 edges)")
    @test_disp(v,
        """
        EdgesMaskView<trophic>{Bool} (5×5: 6 edges)
         · 1 1 · ·
         · · 1 · 1
         · · · · ·
         · · 1 · 1
         · · · · ·\
        """
    )

    # The view has some basic matrix-like interface.
    A = sparse([
        0 1 1 0 0
        0 0 1 0 1
        0 0 0 0 0
        0 0 1 0 1
        0 0 0 0 0
    ])
    @test v == collect(v) == [i for i in v] == A
    # The view may be extracted into a regular sparse matrix.
    e = extract(v)
    @test e isa SparseMatrix{Bool}
    @test e == v == A

    # Either index with integers or labels, also converted data input.
    @test v[1, 1] == false
    @test v[0x1, 0x2] == true
    @test v[:a, :c] == true
    @test v['a', "d"] == false
    @test v[1, :b] == true
    @test v[:b, 1] == false

    # Natural markers & ranges.
    @test v[1, end] == false
    a = v[2, 3:5]
    b = v[1:(end-1), 3]
    c = v[2:3, ((end-1):end)]
    @test a isa SparseVector{Bool}
    @test b isa SparseVector{Bool}
    @test c isa SparseMatrix{Bool}
    @test a == [1, 0, 1]
    @test b == [1, 1, 0, 1]
    @test c == [
        0 1
        0 0
    ]

    # Boolean masks.
    k = [
        0 1 0 0 0
        0 0 1 0 1
        0 1 1 1 0
        0 0 1 0 0
        0 0 0 0 1
    ]
    @test v[k] isa SparseVector{Bool}
    @test v[k] == v[sparse(k)] == v[Bool.(k)] == [1, 0, 1, 0, 1, 0, 1, 0]

    @viewfails(v[],
        (d, (), :whole, nothing, "Edge-level data has 2 dimensions, received 0."))
    @viewfails(v[1],
        (d, (1,), :whole, nothing, "Edge-level data has 2 dimensions, received 1."))
    @viewfails(v[1, 2, 3],
        (d, (1, 2, 3), :whole, nothing, "Edge-level data has 2 dimensions, received 3."))
    @viewfails(v[true, false],
        (d, true, (1,), nothing,
            "Views are queried with indices [::Int] or labels [::Symbol], not `$Bool`."))
    @viewfails(v[(1, 2)],
        (d, (1, 2), (1,), nothing, "Cannot index into views with explicit tuples."))
    @viewfails(v[0x8000000000000000, 2],
        (d, 0x8000000000000000, (1,), nothing,
            "Index too large to be used with julia arrays (9223372036854775808)."))
    @viewfails(v[-5, 2],
        (d, -5, (1,), nothing, "Integer node references can only be positive."))
    @viewfails(v[[0 1; 2 3]],
        (d, 2, (1, (2, 1)), nothing,
            "Could not interpret as a boolean mask:\n\
             Cannot convert to `$(SparseMatrix{Bool})`:\n\
             (detail down the stacktrace)"))
    @viewfails(v[6, 7],
        (d, 6, (1,), nothing, "The source class (:species) only contains 5 nodes."))
    @viewfails(v[5, 7],
        (d, 7, (2,), nothing, "The target class (:species) only contains 5 nodes."))
    @viewfails(v[:x, 3],
        (d, :x, (1,), nothing, "No node in the source class (:species) is labeled :x."))
    @viewfails(v[3, :y],
        (d, :y, (2,), nothing, "No node in the target class (:species) is labeled :y."))
    @viewfails(v[end+1, 2],
        (d, 6, (1,), nothing, "The source class (:species) only contains 5 nodes."))
    @viewfails(v[2, (end-1):(end+1)],
        (d, 6, (2, (:last,)), nothing,
            "The target class (:species) only contains 5 nodes."))
    @viewfails(v[[0 1 0]],
        (d, sparse(Bool[0 1 0]), (1,), nothing,
            "There are (5, 5) potential edges but the given mask is of size (1, 3)."))

    # Multi-dim.
    @test_err(v[2, false],
        """
        Cannot index into <trophic> with [2, false]:
        On dimension 2:
        Views are queried with indices [::Int] or labels [::Symbol], not `$Bool`.
        Received: false  ::$Bool\
        """)
    @test_err(v[[0 1 0]],
        """
        There are (5, 5) potential edges but the given mask is of size (1, 3).
        Cannot index into <trophic> with: [
          (sparse([1], [2], Bool[1], 1, 3),)  ::$Tuple{$(SparseMatrix{Bool})},
        ]\
        """)

    # Immutable, prior to any indexing guard.
    @immutfails((v[1, 1] = true), View)
    @immutfails((v[:a, :b] = false), View)
    @immutfails((v[1:2, 2:end] = false), View)
    @immutfails((v[] = true), View)
    @immutfails((v[1, 2, 3] = true), View)
    @immutfails((v[nothing] = true), View)
    @immutfails((v[nothing, 1] = true), View)
    @immutfails((v[1, nothing] = true), View)

    # Although the *blueprint* can be mutated.
    @test Model(Species("abcde"), bp).trophic.mask[:a, :d] == false
    push!(bp.A[:a], :d)
    @test Model(Species("abcde"), bp).trophic.mask[:a, :d] == true

end

@testset "Web component: expansion semantics" begin

    # Same matrix.
    @test Model(Foodweb([0; 1;; 0; 0])).trophic.matrix == [0; 1;; 0; 0]

    # Matrix ordering matches the parsed nodes ordering.
    md = Model(Foodweb([:a => :b]))
    @test md.species.names == [:a, :b]
    @test md.trophic.matrix == [
        0 1
        0 0
    ]
    md = Model(Foodweb([2 => 1]))
    @test md.species.names == [:s1, :s2]
    @test md.trophic.matrix == [
        0 0
        1 0
    ]


    # Missing nodes are interpolated as isolated.
    @test Model(Foodweb([1 => 4])).trophic.matrix == [
        0 0 0 1
        0 0 0 0
        0 0 0 0
        0 0 0 0
    ]

end

end
