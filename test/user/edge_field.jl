"Test all aspects of typical EdgeField component, using efficiency as an example."
module EdgeFieldTest

# Much inspired by `NodeFieldTest`.

using EcologicalNetworksDynamics
using SparseArrays

import EcologicalNetworksDynamics.Tests:
    EN, N, F, NF, D, V,
    @test_repr, @test_disp, @bpfails, addfails, @viewfails, @checkfails, SparseMatrix,
    @test_err
using Test

const d, _D = D.EdgeField(:trophic, :efficiency)
const View = V.SparseEdgeFieldView{d,Float64}
# TODO: test for dense constructs when such a component shows up.

@testset "EdgeField components: blueprints" begin

    @test Efficiency isa Component
    @test_disp(Efficiency,
        """
        Efficiency (component for $(N.Network), expandable from:
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
        (d, :x, (:u, (3,)), "Cannot convert to `$Float64`:\nConversion not implemented."))
    @checkfails(Efficiency(invalid), d, invalid, :uwhole,
        """
        Cannot convert input to either:
          - $(Float64)
          - $(Vector{Float64})
          - $(NF.SparseMatrix{Float64})
          - $(NF.Adjacency{Float64})
        (see attempts down the stacktrace)\
        """)

    # In particular, reject non-1D arrays.
    invalid = [0.1 0.2; 0.3 0.4]
    @bpfails(Efficiency.Raw(invalid), Efficiency.Raw, :construct,
        (d, invalid, :uwhole,
            "Cannot convert to `$(Vector{Float64})`:\n\
             Would not convert vector to matrix, vice-versa or etc."))

    #---------------------------------------------------------------------------------------
    # Early check.

    @bpfails(Efficiency([0.1, 1.5, 0.3]), Efficiency.Raw, :construct,
        (d, 1.5, (:u, (2,)), "Value must belong to [0, 1]."))
    alias[3] *= -1
    addfails.@check(base + bp, [],
        (Efficiency.Raw, :early, (d, -0.8, (:u, (3,)), "Value must belong to [0, 1].")))

    #---------------------------------------------------------------------------------------
    # Late check.

    addfails.@check(base + Efficiency([0.1, 0.2, 0.3]), [],
        (Efficiency.Raw, :late,
            (d, [0.1, 0.2, 0.3], :mwhole,
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
    @test bp.e isa NF.SparseMatrix{Float64}
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
        (d, :x, (:u, (2, 1)),
            "Cannot convert to `$(SparseMatrix{Float64})`:\n\
             Element cannot be compared to null/zero."))

    @checkfails(Efficiency(invalid), d, invalid, :uwhole,
        """
        Cannot convert input to either:
          - $(Float64)
          - $(Vector{Float64})
          - $(NF.SparseMatrix{Float64})
          - $(NF.Adjacency{Float64})
        (see attempts down the stacktrace)\
        """)

    #---------------------------------------------------------------------------------------
    # Early check.

    @bpfails(Efficiency([0.1 0.2; 3 0.4]), Efficiency.Matrix, :construct,
        (d, 3.0, (:u, (2, 1)), "Value must belong to [0, 1]."))
    alias[4, 3] *= 10
    addfails.@check(base + bp, [],
        (Efficiency.Matrix, :early,
            (d, 4.0, (:u, (4, 3)), "Value must belong to [0, 1].")))

    #---------------------------------------------------------------------------------------
    # Late check.

    addfails.@check(base + Efficiency([0.1 0.2; 0.3 0.4]), [],
        (Efficiency.Matrix, :late,
            (d, sparse([0.1 0.2; 0.3 0.4]), :mwhole,
                "There are 4 sources and 4 targets, \
                 but the matrix received is of size (2, 2).")))

    bp = Efficiency(e)
    bp.e[2, 3] = 0
    droptol!(bp.e, 0)
    addfails.@check(base + bp, [],
        (Efficiency.Matrix, :late,
            (d, bp.e, :mwhole,
                """
                Missing: no (structural) value provided for edge (2, :b) => (3, :c).
                To explicitly make it null, \
                try something along `efficiency[2, 3] = 0` (or equivalent).\
                """)))

    bp.e[4, 3] = 0
    droptol!(bp.e, 0)
    addfails.@check(base + bp, [], # (pluralized)
        (Efficiency.Matrix, :late,
            (d, bp.e, :mwhole,
                """
                Missing: no (structural) values provided for edges \
                (2, :b) => (3, :c) and (4, :d) => (3, :c).
                To explicitly make them null, \
                try something along `efficiency[2, 3] = 0` etc. (or equivalent).\
                """)))

    bp = Efficiency(e)
    bp.e[2, 4] = 0.5
    addfails.@check(base + bp, [],
        (Efficiency.Matrix, :late,
            (d, [(2, 4) => 0.5], :mwhole,
                "Received unexpected value: \
                 there is no such :trophic edge: (2, :b) => (4, :d).")))

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

    bp_r = Efficiency.Adjacency(adj_r)
    bp_i = Efficiency.Adjacency(adj_i)
    @test bp_r.e isa NF.Adjacency{Float64,Symbol}
    @test bp_i.e isa NF.Adjacency{Float64,Int}
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
        (d, 0.5, (:u, [1, :right, 1]),
            "Cannot interpret target reference as integer index or symbol label."))
    @checkfails(Efficiency(invalid), d, invalid, :uwhole,
        """
        Cannot convert input to either:
          - $(Float64)
          - $(Vector{Float64})
          - $(NF.SparseMatrix{Float64})
          - $(NF.Adjacency{Float64})
        (see attempts down the stacktrace)\
        """)

    #---------------------------------------------------------------------------------------
    # Early check.

    @bpfails(Efficiency([:a => (:b, 5)]), Efficiency.Adjacency, :construct,
        (d, 5.0, (:u, (:a, :b)), "Value must belong to [0, 1]."))
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
            (d, 4.0, (:u, (:d, :c)), "Value must belong to [0, 1].")))

    bp_i.e[4][3] *= 10
    addfails.@check(base + bp_i, [],
        (Efficiency.Adjacency, :early,
            (d, 4.0, (:u, (4, 3)), "Value must belong to [0, 1].")))

    #---------------------------------------------------------------------------------------
    # Late check.

    bp_r, bp_i = Efficiency.((adj_r, adj_i))
    pop!(bp_r.e, :b)
    pop!(bp_i.e, 2)

    for bp in (bp_r, bp_i)
        addfails.@check(base + bp, [],
            (Efficiency.Adjacency, :late,
                (d, bp.e, :mwhole,
                    "Missing: no (structural) value provided for edge (2, :b) => (3, :c).\n\
                     To explicitly make it null, \
                     try something along `efficiency[2][3] = 0` (or equivalent).")))
    end

    bp_r.e[:x] = Efficiency(adj_r).e[:b] # TODO: better ergonomics to add superlevel entry?
    bp_i.e[5] = Efficiency(adj_i).e[2]

    addfails.@check(base + bp_r, [],
        (Efficiency.Adjacency, :late,
            (d, (:x, :c), (:u, (:x, :c)), "Not a species node label: :x.")))
    addfails.@check(base + bp_i, [],
        (Efficiency.Adjacency, :late,
            (d, (5, 3), (:u, (5, 3)), "Not an index among 4 species nodes: 5.")))

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
    # ↑ ↑ ↑ HERE update tests ↑ ↑ ↑
    # ======================================================================================
    error("STOP HERE")

    # ======================================================================================
    # Adjacency blueprint.

    #---------------------------------------------------------------------------------------
    # Construct (with labels or integer references).

    @bpfails(
        Efficiency.Adjacency([:a => (:b => :x)]),
        "When constructing <trophic:efficiency> from an adjacency list:\n\
         Expected values of type '$Float64', \
         received instead at [1][right][right]: :x ::$Symbol."
    )
    @bpfails(
        Efficiency.Adjacency([1 => (2 => -1)]),
        "When constructing <trophic:efficiency> from an adjacency list:\n\
         On edge [1, 2]:\n\
         Value must belong to [0, 1].",
        -1.0,
    )

    #---------------------------------------------------------------------------------------
    # Early check.

    addfails.@check(
        let
            b = deepcopy(bp_r)
            b.e[:d][:a] *= 15
            base + b
        end,
        Check(
            early,
            [Efficiency.Adjacency],
            """
            When checking <trophic:efficiency> blueprint data:
            On edge :d => :a:
            Value must belong to [0, 1].
            Received: 1.5\
            """,
        )
    )

    addfails.@check(
        let
            b = deepcopy(bp_i)
            b.e[4][1] *= 15
            base + b
        end,
        Check(
            early,
            [Efficiency.Adjacency],
            """
            When checking <trophic:efficiency> blueprint data:
            On edge [4, 1]:
            Value must belong to [0, 1].
            Received: 1.5\
            """,
        )
    )

    # Break adjacency list (guarded by a reparse).
    addfails.@check(
        let
            b = deepcopy(bp_i)
            b.e[1][-1] = 0.8
            base + b
        end,
        Check(
            early,
            [Efficiency.Adjacency],
            "When checking <trophic:efficiency> blueprint data:\n\
             Integer reference must be a positive index. \
             Received at [1][right][2][left]: -1 ::$Int.",
        )
    )

    #---------------------------------------------------------------------------------------
    # Late check.

    addfails.@check(
        let
            b = deepcopy(bp_r)
            pop!(b.e, :d)
            base + b
        end,
        Check(
            late,
            [Efficiency.Adjacency],
            "When checking <trophic:efficiency> blueprint against model:\n\
             Edge [:d, :a] has no value in the provided adjacency list.",
        )
    )

    addfails.@check(
        let
            b = deepcopy(bp_i)
            b.e[1][3] = 0.5
            base + b
        end,
        Check(
            late,
            [Efficiency.Adjacency],
            "When checking <trophic:efficiency> blueprint against model:\n\
             Edge [1, 3] does not exist in :trophic \
             but the adjacency list provides a value for it: 0.5.",
        )
    )

    #---------------------------------------------------------------------------------------
    # Expand.

    for bp in (bp_r, bp_i)
        local m = base + bp_r
        @test extract(m.efficiency) == sparse([
            0 2 0 0
            0 0 3 0
            0 0 0 0
            1 0 4 0
        ] / 10)
        # The underlying web and nodes can be implied from the lists.
        m = Model(bp)
        @test m.foodweb.A == [
            0 1 0 0
            0 0 1 0
            0 0 0 0
            1 0 1 0
        ]
        @test m.species.names == if NF.reftype(bp.e) === Symbol
            [:a, :b, :c, :d]
        else
            [:s1, :s2, :s3, :s4]
        end
    end

    # ======================================================================================
    # Flat blueprint.

    #---------------------------------------------------------------------------------------
    # Construct.

    bp = Efficiency.Flat(0.5)
    @test Efficiency.Flat(true) == Efficiency.Flat(1.0) # Input conversion.
    @test bp == Efficiency(0.5) # Implicit constructor.
    @test Efficiency(true) == Efficiency(1.0)
    @test_repr(bp, "<Efficiency>:Flat(e: 0.5)")
    @test_disp(
        bp,
        "blueprint for <Efficiency>: Flat {\n  \
           e: 0.5,\n\
         }",
    )

    @bpfails(
        Efficiency(5),
        "When constructing <trophic:efficiency> from a flat value:\n\
         Value must belong to [0, 1].",
        5.0
    )

    #---------------------------------------------------------------------------------------
    # Early check.

    addfails.@check(
        let
            b = deepcopy(bp)
            b.e = 5
            base + b
        end,
        Check(
            early,
            [Efficiency.Flat],
            """
            When checking <trophic:efficiency> blueprint data:
            Value must belong to [0, 1].
            Received: 5.0\
            """,
        ),
    )

    #---------------------------------------------------------------------------------------
    # Late check.
    # <no example to be tested yet>

    #---------------------------------------------------------------------------------------
    # Expand.

    m = base + bp
    #! format: off
    @test extract(m.efficiency) == [
         0 .5  0  0
         0  0 .5  0
         0  0  0  0
        .5  0 .5  0
    ]
    #! format: on

    # ======================================================================================
    # Views.

    # Cannot access without the data.
    addfails.@check(
        Model().efficiency,
        Property(
            efficiency,
            "Component $(EN._Efficiency) is required to read this property.",
        )
    )

    #---------------------------------------------------------------------------------------
    # Read.

    m = base + Efficiency(mat)
    v = m.efficiency
    @test v isa View
    @test v isa AbstractMatrix{Float64}
    @test_repr(v, "<trophic:efficiency>(4×4: 4 values ranging from 0.1 to 0.4)")
    @test_disp(
        v,
        """
        EdgeDataView<trophic:efficiency>{Float64} (4×4: 4 values)
           · 0.2   · ·
           ·   · 0.3 ·
           ·   ·   · ·
         0.1   · 0.4 ·\
         """,
    )

    # Basic matrix-like interface.
    @test v == collect(v) == mat == [i for i in v]

    # Extract as a regular sparse matrix.
    e = extract(v)
    @test e isa SparseMatrix{Float64}
    @test e == v

    # "same-type-value"
    function stv(exp, act)
        @test typeof(exp) == typeof(act)
        @test exp == act
    end

    # Index with either integers or labels.
    stv(v[4, 1], 0.1)
    stv(v[1, 1], 0.0) # Obtain null values off-web.
    stv(v[:a, :b], 0.2)
    stv(v[:b, 3], 0.3)
    stv(v[4, :c], 0.4)
    stv(v[1:2, 3], sparse([0, 0.3]))
    stv(v[1, 1:2], sparse([0, 0.2]))
    stv(v[1:2, 2:3], sparse([0.2 0; 0 0.3]))
    stv(v[2:(end-1), 3], sparse([0.3, 0]))
    stv(v[2, 2:(end-1)], sparse([0, 0.3]))
    stv(v[2:(end-1), 2:(end-1)], sparse([0 0.3; 0 0]))


    @viewfails(v[], View, "Two indices are required to index into webs. Received 0: [].")
    for single in (nothing, 1, :a)
        @viewfails(
            v[single],
            View,
            "Two indices are required to index into webs. Received 1: [$(repr(single))]."
        )
    end
    @viewfails(
        v[1, 2, 3],
        View,
        "Two indices are required to index into webs. Received 3: [1, 2, 3]."
    )
    for wrong in (0, 5)
        @viewfails(
            v[wrong, 2],
            View,
            "Cannot index with [$wrong, ·] into a :trophic web with 4 species source nodes."
        )
        @viewfails(
            v[2, wrong],
            View,
            "Cannot index with [·, $wrong] into a :trophic web with 4 species target nodes."
        )
    end
    @viewfails(
        v[:x, 2],
        View,
        "Cannot index with [:x, ·] into this :trophic web \
         because :x is not a node label in source class :species."
    )
    @viewfails(
        v[2, :x],
        View,
        "Cannot index with [·, :x] into this :trophic web \
         because :x is not a node label in target class :species."
    )
    for invalid in [() -> v[nothing, 1], () -> v[1, nothing]]
        @viewfails(
            invalid(),
            View,
            "Views are indexed with indices (::Int) or labels (::Symbol). \
             Cannot index with: nothing ::Nothing."
        )
    end

    #---------------------------------------------------------------------------------------
    # Write.

    w = m.efficiency # Alternate view to the same model.
    alt = copy(m) # Forked model.
    a = alt.efficiency # Alternate view to the forked model.
    @test a == w == mat

    # Mutate, invoking COW.
    #  v[1, 2] += .7 # HERE: make it work.

    # TODO: once all tests pass here, do cleanup view indexing code,
    # could be much more compact with check_ref, to_index, _is_edge etc.

end

@testset "WebField components: expansion semantics" begin
    # TODO: check that .Raw expansion is column-wise.
    # TODO: check .{Matrix,Adjacency,Flat} expansion results.
end

end
