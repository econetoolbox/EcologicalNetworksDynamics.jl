"Test all aspects of typical EdgeField component, using efficiency as an example."
module EdgeFieldTest

# Much inspired by `NodeFieldTest`.

using EcologicalNetworksDynamics
using SparseArrays

import EcologicalNetworksDynamics.Tests:
    EN, ST, CS, IT, SL, VW,
    @test_repr, @test_disp, @bpfails, addfails, @viewfails, @checkfails, SparseMatrix,
    @propfails, @test_err, @mutfails
using Test

const s, S = SL.EdgeField(:trophic, :efficiency)
const View = VW.SparseEdgeFieldView{s,Float64}
const Tr = CS.@PropertySpace(trophic, ST.Network)
# TODO: test for dense constructs when such a component shows up: nutrients-to-consumers?

@testset "EdgeField components: blueprints" begin

    @test Efficiency isa Component
    @test_disp(Efficiency,
        """
        Efficiency (component for $(ST.Network), expandable from:
          Raw: raw values,
          Matrix: a sparse matrix,
          Adjacency: [species => [species => efficiency]] adjacency list,
          Flat: uniform value,
          Miele2019: herbivorous/carnivorous efficiencies,
        )\
        """,
    )
    @test Efficiency.Raw <: EN.Blueprint
    @test Efficiency.Matrix <: EN.Blueprint
    @test Efficiency.Adjacency <: EN.Blueprint
    @test Efficiency.Flat <: EN.Blueprint

    base = Model(Foodweb([
        :a => :b,
        :b => :c,
        :d => (:a, :c),
    ]))

    # ======================================================================================
    # From raw values.

    #---------------------------------------------------------------------------------------
    # Construct.

    bp = Efficiency.Raw([2, 5, 8, 4] / 10)
    @test bp.e isa Vector{Float64}
    @test bp == Efficiency([2, 5, 8, 4] / 10)
    @test Efficiency.Raw(Bool[0, 1, 0, 1]).e == [0, 1, 0, 1]
    @test Efficiency(Bool[0, 1, 0, 1]).e == [0, 1, 0, 1]
    @test_repr(bp, "<Efficiency>:Raw(e: [0.2, 0.5, 0.8, 0.4])")
    @test_disp(bp,
        """
        blueprint for <Efficiency>: Raw {
          e: [0.2, 0.5, 0.8, 0.4],
        }\
        """,)

    alias = bp.e
    @test alias === Efficiency.Raw(alias).e
    @test alias === Efficiency(alias).e

    invalid = [4, 5, :x]
    @bpfails(Efficiency.Raw(invalid), Efficiency.Raw, :construct,
        (s, :x, (:u, (3,)), "Cannot convert to `$Float64`:\nConversion not implemented."))
    @checkfails(Efficiency(invalid), s, invalid, :uwhole,
        """
        Cannot convert input to either:
          - $(Float64)
          - $(Vector{Float64})
          - $(IT.SparseMatrix{Float64})
          - $(IT.Adjacency{Float64})
        (see attempts down the stacktrace)\
        """)

    # In particular, reject non-1D arrays.
    invalid = [0.1 0.2; 0.3 0.4]
    @bpfails(Efficiency.Raw(invalid), Efficiency.Raw, :construct,
        (s, invalid, :uwhole,
            "Cannot convert to `$(Vector{Float64})`:\n\
             Would not convert vector to matrix, vice-versa or etc."))

    #---------------------------------------------------------------------------------------
    # Early check.

    @bpfails(Efficiency([0.1, 1.5, 0.3]), Efficiency.Raw, :construct,
        (s, 1.5, (:u, (2,)), "Value must belong to [0, 1]."))
    alias[3] *= -1
    addfails.@check(base + bp, [],
        (Efficiency.Raw, :early, (s, -0.8, (:u, (3,)), "Value must belong to [0, 1].")))

    #---------------------------------------------------------------------------------------
    # Late check.

    addfails.@check(base + Efficiency([0.1, 0.2, 0.3]), [],
        (Efficiency.Raw, :late,
            (s, [0.1, 0.2, 0.3], :mwhole,
                "There are 4 edges to valuate, but the vector is of size 3.")))

    #---------------------------------------------------------------------------------------
    # Expand.

    bp = Efficiency.Raw([2, 5, 8, 4] / 10)
    m = base + bp
    @test has_component(m, Efficiency)
    @test_disp(m,
        """
        Model (alias for $Model) with 3 components:
          - Species: 4 (:a, :b, :c, :d)
          - Foodweb: 4 links, 1 producer, 3 consumers, 3 preys, 1 top.
          - Efficiency: 0.2 to 0.8 (4 values).\
        """)

    # The web is required.
    addfails.@missing(Model(bp), Foodweb, Efficiency, [Efficiency.Raw], nothing)

    # ======================================================================================
    # From a matrix.

    e = [
        0 5 0 0
        0 0 8 0
        0 0 0 0
        2 0 4 0
    ] / 10

    #---------------------------------------------------------------------------------------
    # Construct.

    bp = Efficiency.Matrix(e)
    @test bp.e isa IT.SparseMatrix{Float64}
    @test bp == Efficiency(e)
    @test Efficiency.Matrix(Bool[0 1; 1 0]).e == [0 1; 1 0]
    @test Efficiency(Bool[0 1; 1 0]).e == [0 1; 1 0]
    @test_repr(bp, "<Efficiency>:Matrix(e: 4×4:4 [0.2:0.8])")
    @test_disp(bp,
        """
        blueprint for <Efficiency>: Matrix {
          e: 4×4 sparse matrix with 4 values (0.2 to 0.8),
        }\
       """
    )

    alias = bp.e
    @test alias === Efficiency.Matrix(alias).e
    @test alias === Efficiency(alias).e

    invalid = [0.4 0.5; :x 0.8]
    @bpfails(Efficiency.Matrix(invalid), Efficiency.Matrix, :construct,
        (s, :x, (:u, (2, 1)),
            "Cannot convert to `$(SparseMatrix{Float64})`:\n\
             Element cannot be compared to null/zero."))

    @checkfails(Efficiency(invalid), s, invalid, :uwhole,
        """
        Cannot convert input to either:
          - $(Float64)
          - $(Vector{Float64})
          - $(IT.SparseMatrix{Float64})
          - $(IT.Adjacency{Float64})
        (see attempts down the stacktrace)\
        """)

    #---------------------------------------------------------------------------------------
    # Early check.

    @bpfails(Efficiency([0.1 0.2; 3 0.4]), Efficiency.Matrix, :construct,
        (s, 3.0, (:u, (2, 1)), "Value must belong to [0, 1]."))
    alias[4, 3] *= 10
    addfails.@check(base + bp, [],
        (Efficiency.Matrix, :early,
            (s, 4.0, (:u, (4, 3)), "Value must belong to [0, 1].")))

    #---------------------------------------------------------------------------------------
    # Late check.

    addfails.@check(base + Efficiency([0.1 0.2; 0.3 0.4]), [],
        (Efficiency.Matrix, :late,
            (s, sparse([0.1 0.2; 0.3 0.4]), :mwhole,
                "There are 4 sources and 4 targets, \
                 but the matrix received is of size (2, 2).")))

    bp = Efficiency(e)
    bp.e[2, 3] = 0
    droptol!(bp.e, 0)
    addfails.@check(base + bp, [],
        (Efficiency.Matrix, :late,
            (s, bp.e, :mwhole,
                """
                Missing: the trophic edge (2, :b) => (3, :c) exists, \
                but no value is provided for it.
                To explicitly make it null, \
                try something along `efficiency[2, 3] = 0` (or equivalent).\
                """)))

    bp.e[4, 3] = 0
    droptol!(bp.e, 0)
    addfails.@check(base + bp, [], # (pluralized)
        (Efficiency.Matrix, :late,
            (s, bp.e, :mwhole,
                """
                Missing: the trophic edges (2, :b) => (3, :c) and (4, :d) => (3, :c) \
                exist, but no value is provided for them.
                To explicitly make them null, \
                try something along `efficiency[2, 3] = 0` etc. (or equivalent).\
                """)))

    bp = Efficiency(e)
    bp.e[2, 4] = 0.5
    addfails.@check(base + bp, [],
        (Efficiency.Matrix, :late,
            (s, [(2, 4) => 0.5], :mwhole,
                "Received unexpected value: \
                 there is no such trophic edge: (2, :b) => (4, :d).")))

    #---------------------------------------------------------------------------------------
    # Expand.

    bp = Efficiency(e)
    m = base + bp
    @test has_component(m, Efficiency)

    # The web is inferred..
    m = Model(bp)
    @test has_component(m, Species) # .. and therefore the nodes.
    @test has_component(m, Foodweb)
    @test m.species.names == [:s1, :s2, :s3, :s4]
    @test m.trophic.matrix == (e .> 0)

    # ======================================================================================
    # From an adjacency list.

    adj_r = [:a => (:b => 0.2), :b => (:c => 0.3), :d => (:a => 0.1, :c => 0.4)]
    adj_i = [1 => (2 => 0.2), 2 => (3 => 0.3), 4 => (1 => 0.1, 3 => 0.4)]

    #---------------------------------------------------------------------------------------
    # Construct.

    bp_r = Efficiency.Adjacency(adj_r)
    bp_i = Efficiency.Adjacency(adj_i)
    @test bp_r.e isa IT.Adjacency{Float64,Symbol}
    @test bp_i.e isa IT.Adjacency{Float64,Int}
    @test bp_r == Efficiency(adj_r)
    @test bp_i == Efficiency(adj_i)
    @test_repr(bp_r,
        "<Efficiency>:Adjacency(e: {a: {b: 0.2}, b: {c: 0.3}, d: {a: 0.1, c: 0.4}})")
    @test_repr(bp_i,
        "<Efficiency>:Adjacency(e: {1: {2: 0.2}, 2: {3: 0.3}, 4: {1: 0.1, 3: 0.4}})")
    @test_disp(bp_r,
        """
        blueprint for <Efficiency>: Adjacency {
          e: {a: {b: 0.2}, b: {c: 0.3}, d: {a: 0.1, c: 0.4}},
        }\
        """)
    @test_disp(bp_i,
        """
        blueprint for <Efficiency>: Adjacency {
          e: {1: {2: 0.2}, 2: {3: 0.3}, 4: {1: 0.1, 3: 0.4}},
        }\
        """)

    for bp in (bp_r, bp_i)
        alias = bp_r.e
        @test alias === Efficiency.Adjacency(alias).e
        @test alias === Efficiency(alias).e
    end

    invalid = [:a => 0.5]
    @bpfails(Efficiency.Adjacency(invalid), Efficiency.Adjacency, :construct,
        (s, 0.5, (:u, [1, :right, 1]),
            "Cannot interpret target reference as integer index or symbol label."))
    @bpfails(Efficiency.Adjacency([:a => (:b => :x)]), Efficiency.Adjacency, :construct,
        (s, :x, (:u, [1, :right, :right]), "Could not convert to `Float64`."))

    @checkfails(Efficiency(invalid), s, invalid, :uwhole,
        """
        Cannot convert input to either:
          - $(Float64)
          - $(Vector{Float64})
          - $(IT.SparseMatrix{Float64})
          - $(IT.Adjacency{Float64})
        (see attempts down the stacktrace)\
        """)

    #---------------------------------------------------------------------------------------
    # Early check.

    @bpfails(Efficiency([:a => (:b, 5)]), Efficiency.Adjacency, :construct,
        (s, 5.0, (:u, (:a, :b)), "Value must belong to [0, 1]."))
    @bpfails(Efficiency.Adjacency([1 => (2 => -1)]), Efficiency.Adjacency, :construct,
        (s, -1.0, (:u, (1, 2)), "Value must belong to [0, 1]."))
    @test_err(Efficiency([:a => (:b, 5)]),
        """
        While constructing blueprint Efficiency.Adjacency:
        In the provided input at [:a, :b] for <trophic:efficiency>:
        Value must belong to [0, 1].
        Received: 5.0  ::$Float64\
        """
    )

    bp_r.e[:d][:c] *= 10
    addfails.@check(base + bp_r, [],
        (Efficiency.Adjacency, :early,
            (s, 4.0, (:u, (:d, :c)), "Value must belong to [0, 1].")))

    bp_i.e[4][3] *= 10
    addfails.@check(base + bp_i, [],
        (Efficiency.Adjacency, :early,
            (s, 4.0, (:u, (4, 3)), "Value must belong to [0, 1].")))

    bp_i.e[4][3] = 0.4 # Restore.
    bp_i.e[4][-1] = 0.4 # Re-break.
    addfails.@check(base + bp_i, [],
        (Efficiency.Adjacency, :early,
            (s, -1, (:u, (4, -1)), "Integer reference must be a positive index.")))

    #---------------------------------------------------------------------------------------
    # Late check.

    bp_r, bp_i = Efficiency.((adj_r, adj_i))
    pop!(bp_r.e, :b)
    pop!(bp_i.e, 2)

    for (bp, (i, j)) in [(bp_r, (:b, :c)), (bp_i, (2, 3))]
        addfails.@check(base + bp, [],
            (Efficiency.Adjacency, :late,
                (s, bp.e, :mwhole,
                    "Missing: the trophic edge (2, :b) => (3, :c) exists, \
                     but no value is provided for it.\n\
                     To explicitly make it null, try something along \
                     `efficiency[$(repr(i))][$(repr(j))] = 0` (or equivalent).")))
    end

    bp_r, bp_i = Efficiency.((adj_r, adj_i))
    bp_r.e[:a][:c] = 0.5
    bp_i.e[1][3] = 0.5
    for (bp, (i, j)) in [(bp_r, (:a, :c)), (bp_i, (1, 3))]
        addfails.@check(base + bp, [],
            (Efficiency.Adjacency, :late,
                (s, [(i, j) => 0.5], :mwhole,
                    "Received unexpected value: \
                     there is no such trophic edge: (1, :a) => (3, :c).")))
    end

    bp_r.e[:x] = Efficiency(adj_r).e[:b] # TODO: better ergonomics to add superlevel entry?
    bp_i.e[5] = Efficiency(adj_i).e[2]

    addfails.@check(base + bp_r, [],
        (Efficiency.Adjacency, :late,
            (s, (:x, :c), (:u, (:x, :c)), "Not a species node label: :x.")))
    addfails.@check(base + bp_i, [],
        (Efficiency.Adjacency, :late,
            (s, (5, 3), (:u, (5, 3)), "Not an index among 4 species nodes: 5.")))

    #---------------------------------------------------------------------------------------
    # Expand.

    bp_r, bp_i = Efficiency.((adj_r, adj_i))
    mr = base + bp_r
    mi = base + bp_i
    @test has_component(mr, Efficiency)
    @test has_component(mi, Efficiency)

    # The web is inferred.
    mr = Model(bp_r)
    mi = Model(bp_i)
    @test has_component(mr, Efficiency)
    @test has_component(mi, Efficiency)
    @test has_component(mr, Foodweb)
    @test has_component(mi, Foodweb)
    @test has_component(mr, Species)
    @test has_component(mi, Species)
    @test mr.species.names == [:a, :b, :c, :d]
    @test mi.species.names == [:s1, :s2, :s3, :s4]
    @test mr.trophic.matrix == mi.trophic.matrix == [
        0 1 0 0
        0 0 1 0
        0 0 0 0
        1 0 1 0
    ]

    # ======================================================================================
    # From a single value.

    #---------------------------------------------------------------------------------------
    # Construct.

    bp = Efficiency.Flat(0.5)
    @test bp.e isa Float64
    @test bp == Efficiency(0.5)
    @test Efficiency.Flat(1//4) == Efficiency(1//4) == Efficiency(0.25)
    @test Efficiency.Flat(true) == Efficiency(true) == Efficiency(1)
    @test_repr(bp, "<Efficiency>:Flat(e: 0.5)")
    @test_disp(bp,
        """
        blueprint for <Efficiency>: Flat {
          e: 0.5,
        }\
        """)

    @bpfails(Efficiency.Flat(:x), Efficiency.Flat, :construct,
        (s, :x, :uwhole, "Cannot convert to `$Float64`:\nConversion not implemented."))

    #---------------------------------------------------------------------------------------
    # Early check.

    @bpfails(Efficiency(5), Efficiency.Flat, :construct,
        (s, 5.0, :uwhole, "Value must belong to [0, 1]."))

    bp.e *= 3
    addfails.@check(base + bp, [],
        (Efficiency.Flat, :early, (s, 1.5, :uwhole, "Value must belong to [0, 1].")))

    # TODO: any example flat blueprint with anything to late check?
    #---------------------------------------------------------------------------------------
    # Expand.

    bp = Efficiency(0.8)
    m = base + bp
    @test has_component(m, Efficiency)
    @test_disp(m, # Special flat-display.
        """
        Model (alias for $(IT.Model)) with 3 components:
          - Species: 4 (:a, :b, :c, :d)
          - Foodweb: 4 links, 1 producer, 3 consumers, 3 preys, 1 top.
          - Efficiency: 0.8 (4 values).\
        """)

end

@testset "EdgeField components: views" begin

    @propfails(Model().trophic.efficiency, Tr, :efficiency,
        "Component <Efficiency> is required to read this property.")

    e = [
        0 5 0 0
        0 0 8 0
        0 0 0 0
        2 0 4 0
    ] / 10
    m = Model(Species("abcd"), Efficiency(e))

    v = m.trophic.efficiency
    @test v isa View
    @test_repr(v, "<trophic:efficiency>(4×4: 4 values ranging from 0.2 to 0.8)")
    @test_disp(v,
        """
        EdgesFieldView<trophic:efficiency>{Float64} (4×4: 4 values)
           · 0.5   · ·
           ·   · 0.8 ·
           ·   ·   · ·
         0.2   · 0.4 ·\
        """)

    x = extract(v)
    @test x isa SparseMatrix{Float64}
    @test x == e
    @test findnz(x) == findnz(sparse(e))

    # Basic indexing, with integers or labels (or convertable).
    @test v[1, 1] == 0
    @test v[0x1, 0x2] == 0.5
    @test v[:d, :a] == 0.2
    @test v['b', "c"] == 0.8
    @test v[4, "c"] == 0.4
    @test v[first(split("d")), 4] == 0

    # Natural interface inherited from AbstractArray.
    @test v isa AbstractSparseMatrix{Float64}
    @test nnz(v) == 4
    nz = nonzeros(v)
    @test nz isa Vector{Float64}
    @test nz == [0.2, 0.5, 0.8, 0.4] # (colwise)
    sim = similar(v)
    @test sim isa SparseMatrix{Float64}
    @test sim == spzeros(Float64, (4, 4))
    @test findnz(v) == findnz(sparse(e))
    @test v[1, end] == 0
    @test v[end, 1] == 0.2
    a = v[2, 2:4]
    b = v[1:(end-1), 3]
    c = v[1:2, 2:4]
    @test a isa Vector{Float64} # TODO have it be sparse (see web mask view tests).
    @test b isa Vector{Float64}
    @test c isa Matrix{Float64}
    @test a == b == [0, 0.8, 0]
    @test c == [0.5 0 0; 0 0.8 0]
    mask = Bool[
        0 0 0 0
        1 0 1 0
        0 1 1 0
        1 0 1 1
    ]
    @test v[mask] isa Vector{Float64}
    @test v[mask] == v[sparse(mask)] == [0, 0.2, 0, 0.8, 0, 0.4, 0]
    @test v == collect(v) == [i for i in v] == e
    # TODO: feature `v[:a, [:b, :c]]` etc.? (see idem).

    # /!\ These (1D col-major) are (now) supported then. TODO: forbid? (see idem)
    @test length(v) == 16
    @test v[1] == 0
    @test v[4] == 0.2
    @test v[[5, 6]] == [0.5, 0]

    a, b = SL.sides(s)
    @viewfails(v[-5, 2], (a, -5, :uwhole, "There are 4 nodes in this class."))
    @viewfails(v[6, 7], (a, 6, :uwhole, "There are 4 nodes in this class."))
    @viewfails(v[4, 7], (b, 7, :uwhole, "There are 4 nodes in this class."))
    @viewfails(v[:x, 3], (a, :x, :uwhole, "No node in this class is labeled :x."))
    @viewfails(v[3, :y], (b, :y, :uwhole, "No node in this class is labeled :y."))
    @viewfails(v[end+1, 2], (a, 5, :uwhole, "There are 4 nodes in this class."))
    @test_err(v[4, 6],
        """
        Cannot index into <species> with [6]:
        There are 4 nodes in this class.\
        """)

    @test_err(v[], "BoundsError: attempt to access 4×4 $View at index []")
    @test_err(v[1, 2, 3], "BoundsError: attempt to access 4×4 $View at index [1, 2, 3]")
    @test_err(v[true, false], "ArgumentError: invalid index: true of type Bool")
    @test_err(v[(1, 2)], "ArgumentError: invalid index: (1, 2) of type Tuple{$Int, $Int}")
    @test_err(v[0x8000000000000000, 2], "InexactError: convert($Int, 0x8000000000000000)")
    @test_err(v[2, (end-1):(end+1)],
        "BoundsError: attempt to access 4×4 $View at index [2, 3:5]")
    @test_err(v[Bool[0 1 0]],
        "BoundsError: attempt to access 4×4 $View at index [1×3 Matrix{Bool}]")

end

@testset "EdgeField components: mutate" begin

    # Inspired from Nodefield mutation tests.

    e = [
        0 5 0 0
        0 0 8 0
        0 0 0 0
        2 0 4 0
    ] / 10
    m = Model(Species("abcd"), Efficiency(e))
    v = m.e

    # The field is *mutable* through the view.
    w = m.e # Alternate view to the same model.
    alt = copy(m) # Forked model.
    a = alt.e # Alternate view to the forked model.
    @test v == w == a == e # All synced (same underlying storage).

    #---------------------------------------------------------------------------------------
    # Mutate, invoking COW.

    v[1, 2] = 0.6
    v[:b, :c] = 0.7
    @test v == w == m.e == [
        0 6 0 0
        0 0 7 0
        0 0 0 0
        2 0 4 0
    ] / 10
    @test a == alt.e == e # Unchanged.

    # Alternately use the whole property to mutate the 'reassign-like' way.
    input = [
        0 2 0 0
        0 0 3 0
        0 0 0 0
        1 0 4 0
    ] / 10
    m.e = input
    @test v == w == m.e == input

    # Raw-vector style.
    m.e = [5, 6, 7, 8] / 10
    @test v == w == m.e == [
        0 6 0 0
        0 0 7 0
        0 0 0 0
        5 0 8 0
    ] / 10

    # Sophisticated reassign, adjacency-like.
    m.e = [:a => (; b = 0.1), :d => (:c, 0.2)] # (may be partial then)
    @test v == w == m.e == [
        0 1 0 0
        0 0 7 0
        0 0 0 0
        5 0 2 0
    ] / 10
    m.e = [1 => (2 => 0.8), 4 => (3, 0.3)]
    @test v == w == m.e == [
        0 8 0 0
        0 0 7 0
        0 0 0 0
        5 0 3 0
    ] / 10

    # Or flat-like.
    m.e = 0.9
    @test v == w == m.e == 0.9 * m.trophic.mask

    # Still unchanged.
    @test a == alt.e == e

    #---------------------------------------------------------------------------------------
    # Index-check.

    src, tgt = SL.sides(s)
    @viewfails(v[-5, 2] = 8, (src, -5, :uwhole, "There are 4 nodes in this class."))
    @viewfails(v[6, 7] = 8, (src, 6, :uwhole, "There are 4 nodes in this class."))
    @viewfails(v[4, 6] = 8, (tgt, 6, :uwhole, "There are 4 nodes in this class."))
    @viewfails(v[:x, 3] = 8, (src, :x, :uwhole, "No node in this class is labeled :x."))
    @viewfails(v[3, :y] = 8, (tgt, :y, :uwhole, "No node in this class is labeled :y."))
    @viewfails(v[end+1, 2] = 8, (src, 5, :uwhole, "There are 4 nodes in this class."))
    @test_err(v[] = 8, "BoundsError: attempt to access 4×4 $View at index []")
    @test_err(v[1, 2, 3] = 8, "BoundsError: attempt to access 4×4 $View at index [1, 2, 3]")
    @test_err(v[true, false] = 8, "ArgumentError: invalid index: true of type Bool")
    @test_err(v[(1, 2)] = 8,
        "ArgumentError: invalid index: (1, 2) of type Tuple{$Int, $Int}")
    @test_err(v[0x8000000000000000, 2] = 8,
        "InexactError: convert($Int, 0x8000000000000000)")
    @test_err(v[2, (end-1):(end+1)] = 8,
        "BoundsError: attempt to access 4×4 $View at index [2, 3:5]")
    @test_err(v[Bool[0 1 0]] = 8,
        "BoundsError: attempt to access 4×4 $View at index [1×3 Matrix{Bool}]")
    @test_err(v[4:6] = 8,
        "ArgumentError: indexed assignment with a single value to possibly many locations \
         is not supported; perhaps use broadcasting `.=` instead?")

    # Still unchanged (after failures).
    @test v == w == m.e == 0.9 * m.trophic.mask
    @test a == alt.e == e

    #---------------------------------------------------------------------------------------
    # Early-check.

    # The value is still early-checked.
    for (inv, ref) in [
        (() -> v[1, 2] = 5, ((1, :a), (2, :b))),
        (() -> v .= 5, ((1, :a), (1, :a))),
        (() -> v[6:8] .= 5, ((2, :b), (2, :b))),
    ]
        @mutfails(inv(), (s, 5.0, (:m, ref), "Value must belong to [0, 1]."))
    end

    # Matrix.
    wrong = [
        0 2 0 0
        0 0 30 0
        0 0 0 0
        1 0 4 0
    ] / 10 |> sparse # (also covering sparse input)
    @mutfails(m.e = wrong, (s, 3.0, (:u, (2, 3)), "Value must belong to [0, 1]."))

    # Raw.
    @mutfails(m.e = [5, 60, 7, 8] / 10,
        (s, 6.0, (:u, (2,)), "Value must belong to [0, 1]."))

    # Adjacency.
    @mutfails(m.e = [:a => (; b = 0.1), :d => (:c, 2)],
        (s, 2.0, (:u, (:d, :c)), "Value must belong to [0, 1]."))

    wrong = [1 => (-1 => 0.1), 4 => (3, 2)]
    @test_err(m.e = wrong,
        """
        While mutating model:
        In the provided input targetting edge values for <trophic:efficiency>:
        Cannot convert input to either:
          - $Float64
          - $(Vector{Float64})
          - $(SparseMatrix{Float64})
          - $(IT.Adjacency{Float64})
        (see attempts down the stacktrace)
        Received: $wrong  ::$(typeof(wrong))\
        """)

    # Flat.
    @mutfails(m.e = 9, (s, 9.0, :mwhole, "Value must belong to [0, 1]."))

    # Still unchanged (after failures).
    @test v == w == m.e == 0.9 * m.trophic.mask
    @test a == alt.e == e

    #---------------------------------------------------------------------------------------
    # Late-check.

    # Matrix.
    wrong = [
        0 2 0 0
        0 0 3 0
        0 0 0 9
        1 0 4 0
    ] / 10
    @mutfails(m.e = wrong,
        (s, [(3, 4) => 0.9], :mwhole,
            "Received unexpected value: \
             there is no such trophic edge: (3, :c) => (4, :d)."))
    wrong = [
        0 2 0 0
        0 0 0 0
        0 0 0 0
        1 0 4 0
    ] / 10 |> sparse
    @mutfails(m.e = wrong,
        (s, wrong, :mwhole,
            "Missing: the trophic edge (2, :b) => (3, :c) exists, \
             but no value is provided for it.\n\
             To explicitly make it null, try something along \
             `efficiency[2, 3] = 0` (or equivalent)."))

    # Raw.
    wrong = [4, 5, 6] / 10
    @mutfails(m.e = wrong,
        (s, wrong, :mwhole, "There are 4 edges to valuate, but the vector is of size 3."))

    # Adjacency.
    wrong = [:a => (; c = 0.1), :d => (:c, 0.2)]
    @mutfails(m.e = wrong,
        (s, [(:a, :c) => 0.1], :mwhole,
            "Received unexpected value: \
             there is no such trophic edge: (1, :a) => (3, :c)."))
    wrong = [1 => (3 => 0.1), 4 => (3, 0.2)]
    @mutfails(m.e = wrong,
        (s, [(1, 3) => 0.1], :mwhole,
            "Received unexpected value: \
             there is no such trophic edge: (1, :a) => (3, :c)."))

    wrong = [:a => (; x = 0.1), :d => (:c, 0.2)]
    @mutfails(m.e = wrong,
        (s, (:a, :x), (:u, (:a, :x)), "Not a species node label: :x."))

    # Flat.
    @mutfails(m.e = 9, (s, 9.0, :mwhole, "Value must belong to [0, 1]."))

    # Still unchanged (after failures).
    @test v == w == m.e == 0.9 * m.trophic.mask
    @test a == alt.e == e

end

@testset "WebField components: expansion semantics" begin

    base = Model(Foodweb([
        :a => :b,
        :b => :c,
        :d => (:a, :c),
    ]))

    # Column-wise raw vector.
    bp = Efficiency.Raw([2, 5, 8, 4] / 10)
    m = base + bp
    @test m.e == [
        0 5 0 0
        0 0 8 0
        0 0 0 0
        2 0 4 0
    ] / 10

    # Transparent matrix.
    @test (base + Efficiency.Matrix(m.e)).e == m.e

    # Adjacency means source -> target.
    adj_r = [:a => (:b => 0.5), :b => (:c => 0.8), :d => (:a => 0.2, :c => 0.4)]
    adj_i = [1 => (2 => 0.5), 2 => (3 => 0.8), 4 => (1 => 0.2, 3 => 0.4)]
    mr = base + Efficiency(adj_r)
    mi = base + Efficiency(adj_i)
    @test mi.e == mr.e == m.e

    # Flat means all values are the same.
    @test (base + Efficiency.Flat(0.9)).e == [
        0 9 0 0
        0 0 9 0
        0 0 0 0
        9 0 9 0
    ] / 10

end

end
