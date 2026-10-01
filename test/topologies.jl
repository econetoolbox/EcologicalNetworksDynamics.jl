module TestTopologies

using EcologicalNetworksDynamics.Topologies

using Test
import ..Main: @argfails

# Having correct 'show'/display implies that numerous internals are working correctly.
function check_display(top, short, long)
    @test "$top" == short
    io = IOBuffer()
    show(IOContext(io, :limit => true, :displaysize => (20, 40)), "text/plain", top)
    @test String(take!(io)) == long
end

@testset "Topology primitives" begin

    top = Topology()
    add_nodes!(top, Symbol.(collect("abcd")), :species)
    add_nodes!(top, Symbol.(collect("uv")), :nutrients)
    add_edge_type!(top, :trophic)
    add_edge_type!(top, :mutualism)
    add_edge_type!(top, :interference)
    add_edge!(top, :trophic, :a, :b)
    add_edge!(top, :trophic, :a, :c)
    add_edge!(top, :trophic, :c, :b)
    add_edge!(top, :trophic, :b, :d)
    add_edge!(top, :trophic, :d, :u)
    add_edge!(top, :trophic, :b, :v)
    add_edge!(top, :mutualism, :a, :d)
    add_edge!(top, :interference, :a, :c)

    #! format: off
    check_display(top,
       "Topology(2 node types, 3 edge types, 6 nodes, 8 edges)",
    raw"Topology for 2 node types and 3 edge types with 6 nodes and 8 edges:
  Nodes:
    :species => [:a, :b, :c, :d]
    :nutrients => [:u, :v]
  Edges:
    :trophic
      :a => [:b, :c]
      :b => [:d, :v]
      :c => [:b]
      :d => [:u]
    :mutualism
      :a => [:d]
    :interference
      :a => [:c]",
    )
    #! format: on

    # Extract binary matrices:
    @test adjacency_matrix(top, :species, :trophic, :species) == Bool[
        0 1 1 0
        0 0 0 1
        0 1 0 0
        0 0 0 0
    ]
    @test adjacency_matrix(top, :species, :mutualism, :species) == Bool[
        0 0 0 1
        0 0 0 0
        0 0 0 0
        0 0 0 0
    ]
    @test adjacency_matrix(top, :species, :trophic, :nutrients) == Bool[
        0 0
        0 1
        0 0
        1 0
    ]
    @test adjacency_matrix(top, :nutrients, :trophic, :species) == Bool[
        0 0 0 0
        0 0 0 0
    ]

    # Transposed version.
    transpose = true
    @test adjacency_matrix(top, :species, :trophic, :species; transpose) == Bool[
        0 0 0 0
        1 0 1 0
        1 0 0 0
        0 1 0 0
    ]
    @test adjacency_matrix(top, :species, :mutualism, :species; transpose) == Bool[
        0 0 0 0
        0 0 0 0
        0 0 0 0
        1 0 0 0
    ]
    @test adjacency_matrix(top, :species, :trophic, :nutrients; transpose) == Bool[
        0 0 0 1
        0 1 0 0
    ]
    @test adjacency_matrix(top, :nutrients, :trophic, :species; transpose) == Bool[
        0 0
        0 0
        0 0
        0 0
    ]

    g = deepcopy(top)
    remove_node!(g, :b)

    #! format: off
    check_display(g,
       "Topology(2 node types, 3 edge types, 5 nodes, 4 edges)",
    raw"Topology for 2 node types and 3 edge types with 5 nodes and 4 edges:
  Nodes:
    :species => [:a, :c, :d]  <removed: [:b]>
    :nutrients => [:u, :v]
  Edges:
    :trophic
      :a => [:c]
      :d => [:u]
    :mutualism
      :a => [:d]
    :interference
      :a => [:c]",
    )
    #! format: on

    # Pruned adjacency matrices.
    @test adjacency_matrix(g, :species, :trophic, :species) == Bool[
        0 1 0
        0 0 0
        0 0 0
    ]
    @test adjacency_matrix(g, :species, :mutualism, :species) == Bool[
        0 0 1
        0 0 0
        0 0 0
    ]
    @test adjacency_matrix(g, :species, :trophic, :nutrients) == Bool[
        0 0
        0 0
        1 0
    ]
    @test adjacency_matrix(g, :nutrients, :trophic, :species) == Bool[
        0 0 0
        0 0 0
    ]

    # Transposed + pruned.
    transpose = true
    @test adjacency_matrix(g, :species, :trophic, :species; transpose) == Bool[
        0 0 0
        1 0 0
        0 0 0
    ]
    @test adjacency_matrix(g, :species, :mutualism, :species; transpose) == Bool[
        0 0 0
        0 0 0
        1 0 0
    ]
    @test adjacency_matrix(g, :species, :trophic, :nutrients; transpose) == Bool[
        0 0 1
        0 0 0
    ]
    @test adjacency_matrix(g, :nutrients, :trophic, :species; transpose) == Bool[
        0 0
        0 0
        0 0
    ]

    # Request full matrix anyway.
    @test adjacency_matrix(g, :species, :trophic, :species; prune = false) == Bool[
        0 0 1 0
        0 0 0 0
        0 0 0 0
        0 0 0 0
    ]
    @test adjacency_matrix(g, :species, :mutualism, :species; prune = false) == Bool[
        0 0 0 1
        0 0 0 0
        0 0 0 0
        0 0 0 0
    ]
    @test adjacency_matrix(g, :species, :trophic, :nutrients; prune = false) == Bool[
        0 0
        0 0
        0 0
        1 0
    ]
    @test adjacency_matrix(g, :nutrients, :trophic, :species; prune = false) == Bool[
        0 0 0 0
        0 0 0 0
    ]

    # Transposed version.
    transpose = true
    @test adjacency_matrix(g, :species, :trophic, :species; prune = false, transpose) ==
          Bool[
        0 0 0 0
        0 0 0 0
        1 0 0 0
        0 0 0 0
    ]
    @test adjacency_matrix(g, :species, :mutualism, :species; prune = false, transpose) ==
          Bool[
        0 0 0 0
        0 0 0 0
        0 0 0 0
        1 0 0 0
    ]
    @test adjacency_matrix(g, :species, :trophic, :nutrients; prune = false, transpose) ==
          Bool[
        0 0 0 1
        0 0 0 0
    ]
    @test adjacency_matrix(g, :nutrients, :trophic, :species; prune = false, transpose) ==
          Bool[
        0 0
        0 0
        0 0
        0 0
    ]


    # Optionally provide node type so it's not searched.
    h = deepcopy(top)
    remove_node!(h, :b, :species)
    @test g == h

    # Input guards.
    @argfails(
        add_nodes!(top, :a, :newtype),
        "The labels provided cannot be iterated into a collection of symbols. Received: :a."
    )
    @argfails(
        add_nodes!(top, [:a], :newtype),
        "Label :a was already given to a node of type :species."
    )
    @argfails(
        add_nodes!(top, [:x], :species),
        "Node type :species already exists in the topology."
    )
    @argfails(
        add_nodes!(top, [:x], :mutualism),
        "Node type :mutualism would be confused with edge type :mutualism."
    )
    @argfails(
        add_edge_type!(top, :mutualism),
        "Edge type :mutualism already exists in the topology."
    )
    @argfails(
        add_edge_type!(top, :species),
        "Edge type :species would be confused with node type :species."
    )
    @argfails(
        add_edge!(top, :x, :a, :b),
        "Invalid edge type label: :x. \
         Valid labels within this topology \
         are :interference, :mutualism and :trophic."
    )
    @argfails(
        add_edge!(top, :trophic, :x, :b),
        "Invalid node label: :x. \
         Valid labels within this topology \
         are :a, :b, :c, :d, :u and :v."
    )
    @argfails(
        add_edge!(g, :trophic, :a, :b),
        "Node :b has been removed \
         from this topology."
    )
    @argfails(
        add_edge!(top, :trophic, :a, :b),
        "There is already an edge of type :trophic between nodes :a and :b."
    )
    @argfails(
        remove_node!(g, :x),
        "Invalid node label: :x. \
         Valid labels within this topology \
         are :a, :b, :c, :d, :u and :v.",
    )
    @argfails(
        remove_node!(g, :a, :x),
        "Invalid node type label: :x. \
         Valid labels within this topology \
         are :nutrients and :species.",
    )
    @argfails(remove_node!(g, :b), "Node :b was already removed from this topology.")
    @argfails(
        remove_node!(g, :b, :species),
        "Node :b was already removed \
         from this topology."
    )
    @argfails(
        remove_node!(top, :b, :nutrients),
        "Invalid :nutrients node label: :b. \
         Valid labels within this topology \
         are :u and :v."
    )

    # ======================================================================================
    # Add a whole bunch of edges at once.

    #---------------------------------------------------------------------------------------
    # Within a node compartment.

    f = add_edges_within_node_type!(
        deepcopy(g),
        :species,
        :trophic,
        Bool[
            0 0 0 1
            0 0 0 0
            1 0 0 0
            0 0 1 0
        ],
    )
    #! format: off
    check_display(f,
       "Topology(2 node types, 3 edge types, 5 nodes, 7 edges)",
    raw"Topology for 2 node types and 3 edge types with 5 nodes and 7 edges:
  Nodes:
    :species => [:a, :c, :d]  <removed: [:b]>
    :nutrients => [:u, :v]
  Edges:
    :trophic
      :a => [:c, :d]
      :c => [:a]
      :d => [:c, :u]
    :mutualism
      :a => [:d]
    :interference
      :a => [:c]",
    )
    #! format: on

    # Node indices are correctly offset based on their types.
    f = add_edges_within_node_type!(
        deepcopy(g),
        :nutrients,
        :mutualism, # (say)
        Bool[
            0 1
            0 0
        ],
    )
    #! format: off
    check_display(f,
       "Topology(2 node types, 3 edge types, 5 nodes, 5 edges)",
    raw"Topology for 2 node types and 3 edge types with 5 nodes and 5 edges:
  Nodes:
    :species => [:a, :c, :d]  <removed: [:b]>
    :nutrients => [:u, :v]
  Edges:
    :trophic
      :a => [:c]
      :d => [:u]
    :mutualism
      :a => [:d]
      :u => [:v]
    :interference
      :a => [:c]",
    )
    e = Bool[;;] # (https://github.com/domluna/JuliaFormatter.jl/issues/837)
    #! format: on

    @argfails(
        add_edges_within_node_type!(deepcopy(g), :x, :trophic, e),
        "Invalid node type label: :x. \
         Valid labels within this topology \
         are :nutrients and :species."
    )

    @argfails(
        add_edges_within_node_type!(deepcopy(g), :species, :x, e),
        "Invalid edge type label: :x. \
         Valid labels within this topology \
         are :interference, :mutualism and :trophic."
    )

    @argfails(
        add_edges_within_node_type!(deepcopy(g), :species, :trophic, e),
        "The given edges matrix should be of size (4, 4) \
         because there are 4 nodes of type :species. \
         Received instead: (0, 0)."
    )

    @argfails(
        add_edges_within_node_type!(
            deepcopy(g),
            :species,
            :trophic,
            Bool[
                0 1 1 1
                0 0 0 0
                1 0 0 0
                0 0 1 0
            ],
        ),
        "Node :b (index 2) has been removed from this topology, \
         but the given matrix has a nonzero entry in column 2."
    )

    # Watch offset.
    f = remove_node!(deepcopy(g), :u, :nutrients)
    @argfails(
        add_edges_within_node_type!(
            f,
            :nutrients,
            :trophic,
            Bool[
                0 1
                0 0
            ],
        ),
        "Node :u (index 5: 1st within the :nutrients node type) \
         has been removed from this topology, \
         but the given matrix has a nonzero entry in row 1."
    )

    @argfails(
        add_edges_within_node_type!(
            deepcopy(g),
            :species,
            :mutualism,
            Bool[
                0 0 1 1
                0 0 0 0
                1 0 0 0
                0 0 1 0
            ],
        ),
        "There is already an edge of type :mutualism between nodes \
        :a and :d (indices 1 and 4), \
         but the given matrix has a nonzero entry in (1, 4)."
    )

    # Watch offset.
    f = add_edge!(deepcopy(g), :mutualism, :u, :v)
    @argfails(
        add_edges_within_node_type!(
            f,
            :nutrients,
            :mutualism,
            Bool[
                0 1
                0 0
            ],
        ),
        "There is already an edge of type :mutualism between nodes \
         :u and :v (indices 5 and 6: resp. 1st and 2nd within node type :nutrients), \
         but the given matrix has a nonzero entry in (1, 2)."
    )

    #---------------------------------------------------------------------------------------
    # Accross node compartments.

    f = add_edges_accross_node_types!(
        deepcopy(g),
        :species,
        :nutrients,
        :trophic,
        Bool[
            0 1
            0 0
            1 0
            0 0
        ],
    )
    #! format: off
    check_display(f,
       "Topology(2 node types, 3 edge types, 5 nodes, 6 edges)",
    raw"Topology for 2 node types and 3 edge types with 5 nodes and 6 edges:
  Nodes:
    :species => [:a, :c, :d]  <removed: [:b]>
    :nutrients => [:u, :v]
  Edges:
    :trophic
      :a => [:c, :v]
      :c => [:u]
      :d => [:u]
    :mutualism
      :a => [:d]
    :interference
      :a => [:c]",
    )
    e = Bool[;;] # (https://github.com/domluna/JuliaFormatter.jl/issues/837)
    #! format: on

    @argfails(
        add_edges_accross_node_types!(deepcopy(g), :x, :nutrients, :trophic, e),
        "Invalid node type label: :x. \
         Valid labels within this topology \
         are :nutrients and :species."
    )

    @argfails(
        add_edges_accross_node_types!(deepcopy(g), :species, :x, :trophic, e),
        "Invalid node type label: :x. \
         Valid labels within this topology \
         are :nutrients and :species."
    )

    @argfails(
        add_edges_accross_node_types!(deepcopy(g), :species, :nutrients, :x, e),
        "Invalid edge type label: :x. \
         Valid labels within this topology \
         are :interference, :mutualism and :trophic."
    )

    @argfails(
        add_edges_accross_node_types!(deepcopy(g), :species, :species, :trophic, e),
        "Source node types and target node types are the same (:species). \
         Use $add_edges_within_node_type! method instead."
    )

    @argfails(
        add_edges_accross_node_types!(deepcopy(g), :species, :nutrients, :trophic, e),
        "The given edges matrix should be of size (4, 2) \
         because there are 4 nodes of type :species \
         and 2 nodes of type :nutrients. Received instead: (0, 0)."
    )

    # Missing source node.
    @argfails(
        add_edges_accross_node_types!(
            deepcopy(g),
            :species,
            :nutrients,
            :trophic,
            Bool[
                0 1
                1 0
                1 0
                0 0
            ],
        ),
        "Node :b has been removed from this topology, \
         but the given matrix has a nonzero entry in row 2."
    )

    # Missing target node.
    f = remove_node!(deepcopy(g), :u, :nutrients)
    @argfails(
        add_edges_accross_node_types!(
            f,
            :species,
            :nutrients,
            :trophic,
            Bool[
                0 1
                0 0
                1 0
                0 0
            ],
        ),
        "Node :u (index 5: 1st within the :nutrients node type) \
         has been removed from this topology, \
         but the given matrix has a nonzero entry in column 1."
    )

    @argfails(
        add_edges_accross_node_types!(
            deepcopy(g),
            :species,
            :nutrients,
            :trophic,
            Bool[
                0 1
                0 0
                1 0
                1 0
            ],
        ),
        "There is already an edge of type :trophic between nodes \
         :d and :u (indices 4 and 5: \
         resp. 4th and 1st within node types :species and :nutrients), \
         but the given matrix has a nonzero entry in (4, 1)."
    )
end

@testset "Disconnected components." begin

    top = Topology()
    add_nodes!(top, Symbol.(collect("abcd")), :species)
    add_nodes!(top, Symbol.(collect("uv")), :nutrients)
    add_edge_type!(top, :trophic)
    add_edge_type!(top, :mutualism)
    add_edge_type!(top, :interference)
    add_edge!(top, :trophic, :a, :b)
    add_edge!(top, :trophic, :b, :u)
    add_edge!(top, :trophic, :c, :d)
    add_edge!(top, :trophic, :d, :v)
    add_edge!(top, :mutualism, :a, :u)
    add_edge!(top, :interference, :c, :v)

    x, y = disconnected_components(top)
    #! format: off
    check_display(x,
       "Topology(2 node types, 3 edge types, 3 nodes, 3 edges)",
    raw"Topology for 2 node types and 3 edge types with 3 nodes and 3 edges:
  Nodes:
    :species => [:a, :b]  <removed: [:c, :d]>
    :nutrients => [:u]  <removed: [:v]>
  Edges:
    :trophic
      :a => [:b]
      :b => [:u]
    :mutualism
      :a => [:u]
    :interference <none>",
    )
    check_display(y,
       "Topology(2 node types, 3 edge types, 3 nodes, 3 edges)",
    raw"Topology for 2 node types and 3 edge types with 3 nodes and 3 edges:
  Nodes:
    :species => [:c, :d]  <removed: [:a, :b]>
    :nutrients => [:v]  <removed: [:u]>
  Edges:
    :trophic
      :c => [:d]
      :d => [:v]
    :mutualism <none>
    :interference
      :c => [:v]",
    )
    #! format: on

    # Check adjacency matrices on separate components. - - - - - - - - - - - - - - - - - - -
    @test adjacency_matrix(top, :species, :trophic, :species) == Bool[
        0 1 0 0
        0 0 0 0
        0 0 0 1
        0 0 0 0
    ]
    @test adjacency_matrix(top, :species, :trophic, :nutrients) == Bool[
        0 0
        1 0
        0 0
        0 1
    ]
    @test adjacency_matrix(x, :species, :trophic, :species) == Bool[
        0 1
        0 0
    ]
    @test adjacency_matrix(y, :species, :trophic, :species) == Bool[
        0 1
        0 0
    ]
    #! format: off
    @test adjacency_matrix(x, :species, :trophic, :nutrients) == Bool[
        0
        1;;
    ]
    @test adjacency_matrix(y, :species, :trophic, :nutrients) == Bool[
        0
        1;;
    ]
    #! format: on

    transpose = true # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    @test adjacency_matrix(top, :species, :trophic, :species; transpose) == Bool[
        0 0 0 0
        1 0 0 0
        0 0 0 0
        0 0 1 0
    ]
    @test adjacency_matrix(top, :species, :trophic, :nutrients; transpose) == Bool[
        0 1 0 0
        0 0 0 1
    ]
    @test adjacency_matrix(x, :species, :trophic, :species; transpose) == Bool[
        0 0
        1 0
    ]
    @test adjacency_matrix(y, :species, :trophic, :species; transpose) == Bool[
        0 0
        1 0
    ]
    @test adjacency_matrix(x, :species, :trophic, :nutrients; transpose) == Bool[0 1]
    @test adjacency_matrix(y, :species, :trophic, :nutrients; transpose) == Bool[0 1]

    # Without pruning. - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    @test adjacency_matrix(x, :species, :trophic, :species; prune = false) == Bool[
        0 1 0 0
        0 0 0 0
        0 0 0 0
        0 0 0 0
    ]
    @test adjacency_matrix(y, :species, :trophic, :species; prune = false) == Bool[
        0 0 0 0
        0 0 0 0
        0 0 0 1
        0 0 0 0
    ]
    @test adjacency_matrix(x, :species, :trophic, :nutrients; prune = false) == Bool[
        0 0
        1 0
        0 0
        0 0
    ]
    @test adjacency_matrix(y, :species, :trophic, :nutrients; prune = false) == Bool[
        0 0
        0 0
        0 0
        0 1
    ]

    transpose = true # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    @test adjacency_matrix(x, :species, :trophic, :species; transpose, prune = false) ==
          Bool[
        0 0 0 0
        1 0 0 0
        0 0 0 0
        0 0 0 0
    ]
    @test adjacency_matrix(y, :species, :trophic, :species; transpose, prune = false) ==
          Bool[
        0 0 0 0
        0 0 0 0
        0 0 0 0
        0 0 1 0
    ]
    @test adjacency_matrix(x, :species, :trophic, :nutrients; transpose, prune = false) ==
          Bool[
        0 1 0 0
        0 0 0 0
    ]
    @test adjacency_matrix(y, :species, :trophic, :nutrients; transpose, prune = false) ==
          Bool[
        0 0 0 0
        0 0 0 1
    ]


end

end
