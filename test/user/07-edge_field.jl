"""
Test all aspects of typical EdgeField component,
using Efficiency as an example but without testing anything specific to efficiency.
Anything specific to efficiency will be tested in a dedicated file.
"""
module EdgeFieldTest

# What the end user should have to import.
using EcologicalNetworksDynamics
using SparseArrays

# Additional imports only used here for testing purpose.
using Test
using EcologicalNetworksDynamics: EN, N, F, NF, V, EdgeField, SparseMatrix, Adjacency
import Main: is_repr, is_disp, Value, @inputfails, @sysfails, @viewfails
const View = V.SparseEdgesFieldView{EdgeField(:trophic, :efficiency),Float64}

# TODO: test for dense constructs when such a component shows up.

@testset "Typical EdgeField component" begin

    @test Efficiency isa EN.Component
    @test is_repr(Efficiency, "Efficiency")
    @test is_disp(
        Efficiency,
        """
        Efficiency (component for $(N.Network), expandable from:
          Raw: raw values,
          Matrix: a sparse matrix,
          Adjacency: [species => [species => efficiency]] adjacency list,
          Flat: uniform value,
        )\
        """,
    )
    @test Efficiency.Raw <: EN.Blueprint
    @test Efficiency.Adjacency <: EN.Blueprint
    @test Efficiency.Flat <: EN.Blueprint

    base = Model(Foodweb([:a => :b, :b => :c, :d => (:a, :c)]))

    # ======================================================================================
    # Raw blueprint.

    #---------------------------------------------------------------------------------------
    # Construct, regardless of input type.

    bp = Efficiency.Raw([2, 5, 8, 4] / 10)
    @test Efficiency.Raw(Bool[1, 0, 1, 0]) == Efficiency.Raw([1.0, 0.0, 1.0, 0.0])
    @test bp == Efficiency([2, 5, 8, 4] / 10) # Implicit constructor.
    @test Efficiency(Bool[1, 0, 1, 0]) == Efficiency([1.0, 0.0, 1.0, 0.0])
    @test is_repr(bp, "<Efficiency>:Raw(e: [0.2, 0.5, 0.8, 0.4])")
    @test is_disp(
        bp,
        """
        blueprint for <Efficiency>: Raw {
          e: [0.2, 0.5, 0.8, 0.4],
        }\
        """,
    )
    @inputfails(
        Efficiency('x'),
        "Cannot convert input to either:\n  \
          - $Float64\n  \
          - $Vector{$Float64}\n  \
          - $(SparseMatrix{Float64})\n  \
          - $(Adjacency{Float64})",
        'x',
    )
    @inputfails(
        Efficiency([0.1, 1.5, 0.3]),
        "When constructing <trophic:efficiency> from raw values:\n\
         At raw edge value [2]:\n\
         Value must belong to [0, 1].",
        1.5
    )

    #---------------------------------------------------------------------------------------
    # Early check.

    @sysfails(
        let
            b = deepcopy(bp)
            b.e[2] *= 10
            base + b
        end,
        Check(
            early,
            [Efficiency.Raw],
            """
            When checking <trophic:efficiency> blueprint data:
            At raw edge value [2]:
            Value must belong to [0, 1].
            Received: 5.0\
            """,
        )
    )

    #---------------------------------------------------------------------------------------
    # Late check.

    @sysfails(
        base + Efficiency([0.5, 0.8]),
        Check(
            late,
            [Efficiency.Raw],
            """
            When checking <trophic:efficiency> blueprint against model:
            Wrong number of values received: expected 4, got 2.\
            """,
        )
    )

    #---------------------------------------------------------------------------------------
    # Expand.

    m = base + bp
    @test is_disp(
        m,
        """
        Model (alias for $(F.System){$(N.Network)}) with 3 components:
          - Species: 4 (:a, :b, :c, :d)
          - Foodweb: 4 links, 1 producer, 3 consumers, 3 preys, 1 top.
          - Efficiency: 0.2 to 0.8 (4 values).\
        """,
    )

    # The result is col-wise, as a julia user would expect.
    @test extract(m.efficiency) == [
        0 5 0 0
        0 0 8 0
        0 0 0 0
        2 0 4 0
    ] / 10

    # ======================================================================================
    # Matrix blueprint.

    #---------------------------------------------------------------------------------------
    # Construct from a matrix (sparse in this example).

    mat = sparse([
        0 2 0 0
        0 0 3 0
        0 0 0 0
        1 0 4 0
    ] / 10)
    bp = Efficiency.Matrix(mat)
    @test Efficiency.Matrix(Bool[0 1; 1 0]) == Efficiency.Matrix([0.0 1.0; 1.0 0.0])
    @test bp == Efficiency.Matrix(Matrix(mat)) # From a dense matrix as well.
    @test bp == Efficiency(mat) # Implicit constructor.
    @test is_repr(bp, "<Efficiency>:Matrix(e: 4×4:4 [0.1:0.4])")
    @test is_disp(
        bp,
        """
        blueprint for <Efficiency>: Matrix {
          e: 4×4 sparse matrix with 4 values (0.1 to 0.4),
        }\
        """,
    )

    @inputfails(
        Efficiency([0.1 0.5; -1 0.2]),
        "When constructing <trophic:efficiency> from a matrix:\n\
         On edge [2, 1]:\n\
         Value must belong to [0, 1].",
        -1.0
    )

    #---------------------------------------------------------------------------------------
    # Early check.

    @sysfails(
        let
            b = deepcopy(bp)
            b.e[5] *= 10
            base + b
        end,
        Check(
            early,
            [Efficiency.Matrix],
            """
            When checking <trophic:efficiency> blueprint data:
            On edge [1, 2]:
            Value must belong to [0, 1].
            Received: 2.0\
            """,
        )
    )

    #---------------------------------------------------------------------------------------
    # Late check.

    @sysfails(
        base + Efficiency(zeros(2, 3)),
        Check(
            late,
            [Efficiency.Matrix],
            """
            When checking <trophic:efficiency> blueprint against model:
            The expected topology size for :trophic is 4×4 \
            but the matrix provided is 2×3.\
            """,
        )
    )

    @sysfails(
        base + Efficiency(zeros(4, 4)),
        Check(
            late,
            [Efficiency.Matrix],
            """
            When checking <trophic:efficiency> blueprint against model:
            Edge [1, 2] has no value in the provided sparse matrix.\
            """,
        )
    )

    @sysfails(
        base + Efficiency(ones(4, 4)),
        Check(
            late,
            [Efficiency.Matrix],
            """
            When checking <trophic:efficiency> blueprint against model:
            Edge [3, 1] does not exist in :trophic \
            but the sparse matrix provides a value for it: 1.0.\
            """,
        )
    )

    #---------------------------------------------------------------------------------------
    # Expand.
    m = base + bp

    @test extract(m.efficiency) == sparse([
        0 2 0 0
        0 0 3 0
        0 0 0 0
        1 0 4 0
    ] / 10)

    # The sole matrix structure implies the underlying web, which also implies the class.
    m = Model(bp)
    @test m.foodweb.A == [
        0 1 0 0
        0 0 1 0
        0 0 0 0
        1 0 1 0
    ]
    @test m.species.names == [:s1, :s2, :s3, :s4]

    # ======================================================================================
    # Adjacency blueprint.

    #---------------------------------------------------------------------------------------
    # Construct (with labels or integer references).

    adj_r = [:a => (:b => 0.2), :b => (:c => 0.3), :d => (:a => 0.1, :c => 0.4)]
    adj_i = [1 => (2 => 0.2), 2 => (3 => 0.3), 4 => (1 => 0.1, 3 => 0.4)]
    bp_r = Efficiency.Adjacency(adj_r)
    bp_i = Efficiency.Adjacency(adj_i)
    @test Efficiency.Adjacency([:a => (:b => true, :c => false)]) ==
          Efficiency.Adjacency([:a => (:b => 1.0, :c => 0.0)])
    @test Efficiency.Adjacency([1 => (2 => true, 3 => false)]) ==
          Efficiency.Adjacency([1 => (2 => 1.0, 3 => 0.0)])
    # Implicit constructor.
    @test bp_r == Efficiency(adj_r)
    @test bp_i == Efficiency(adj_i)
    @test is_repr(
        bp_r,
        "<Efficiency>:Adjacency(e: {a: {b: 0.2}, b: {c: 0.3}, d: {a: 0.1, c: 0.4}})",
    )
    @test is_repr(
        bp_i,
        "<Efficiency>:Adjacency(e: {1: {2: 0.2}, 2: {3: 0.3}, 4: {1: 0.1, 3: 0.4}})",
    )
    @test is_disp(
        bp_r,
        """
        blueprint for <Efficiency>: Adjacency {
          e: {a: {b: 0.2}, b: {c: 0.3}, d: {a: 0.1, c: 0.4}},
        }\
        """,
    )
    @test is_disp(
        bp_i,
        """
        blueprint for <Efficiency>: Adjacency {
          e: {1: {2: 0.2}, 2: {3: 0.3}, 4: {1: 0.1, 3: 0.4}},
        }\
        """,
    )

    @inputfails(
        Efficiency.Adjacency([:a => (:b => :x)]),
        "When constructing <trophic:efficiency> from an adjacency list:\n\
         Expected values of type '$Float64', \
         received instead at [1][right][right]: :x ::$Symbol."
    )
    @inputfails(
        Efficiency.Adjacency([1 => (2 => -1)]),
        "When constructing <trophic:efficiency> from an adjacency list:\n\
         On edge [1, 2]:\n\
         Value must belong to [0, 1].",
        -1.0,
    )

    #---------------------------------------------------------------------------------------
    # Early check.

    @sysfails(
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

    @sysfails(
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
    @sysfails(
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

    @sysfails(
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

    @sysfails(
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
    @test is_repr(bp, "<Efficiency>:Flat(e: 0.5)")
    @test is_disp(
        bp,
        "blueprint for <Efficiency>: Flat {\n  \
           e: 0.5,\n\
         }",
    )

    @inputfails(
        Efficiency(5),
        "When constructing <trophic:efficiency> from a flat value:\n\
         Value must belong to [0, 1].",
        5.0
    )

    #---------------------------------------------------------------------------------------
    # Early check.

    @sysfails(
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
    @sysfails(
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
    @test is_repr(v, "<trophic:efficiency>(4×4: 4 values ranging from 0.1 to 0.4)")
    @test is_disp(
        v,
        """
        EdgesDataView<trophic:efficiency>{Float64} (4×4: 4 values)
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

end
