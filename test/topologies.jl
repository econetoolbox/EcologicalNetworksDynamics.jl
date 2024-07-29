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

@testset "Topology construction/edition primitives" begin

    top = Topology()
    add_nodes!(top, Symbol.(collect("abcd")), :species)
    add_nodes!(top, Symbol.(collect("uv")), :nutrients)
    add_edge_type!(top, :trophic)
    add_edge_type!(top, :mutualism)
    add_edge_type!(top, :interference)
    add_edge!(top, :trophic, :a, :b)
    add_edge!(top, :trophic, :c, :b)
    add_edge!(top, :trophic, :b, :d)
    add_edge!(top, :trophic, :d, :u)
    add_edge!(top, :trophic, :b, :v)
    add_edge!(top, :mutualism, :a, :d)
    add_edge!(top, :interference, :a, :c)

    #! format: off
    check_display(top,
       "Topology(2 node types, 3 edge types, 6 nodes, 7 edges)",
    raw"Topology for 2 node types and 3 edge types with 6 nodes and 7 edges:
  Nodes:
    :species => [:a, :b, :c, :d]
    :nutrients => [:u, :v]
  Edges:
    :trophic
      :a => [:b]
      :b => [:d, :v]
      :c => [:b]
      :d => [:u]
    :mutualism
      :a => [:d]
    :interference
      :a => [:c]",
    )
    #! format: on

    u = deepcopy(top)
    remove_node!(u, :b)

    #! format: off
    check_display(u,
       "Topology(2 node types, 3 edge types, 5 nodes, 3 edges)",
    raw"Topology for 2 node types and 3 edge types with 5 nodes and 3 edges:
  Nodes:
    :species => [:a, :c, :d]  <removed: [:b]>
    :nutrients => [:u, :v]
  Edges:
    :trophic
      :d => [:u]
    :mutualism
      :a => [:d]
    :interference
      :a => [:c]",
    )
    #! format: on

    # Optionally provide node type so it's not searched.
    v = deepcopy(top)
    remove_node!(v, :b, :species)
    @test u == v

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
         Valid labels are :interference, :mutualism and :trophic."
    )
    @argfails(
        add_edge!(top, :trophic, :x, :b),
        "Invalid node label: :x. \
         Valid labels are :a, :b, :c, :d, :u and :v."
    )
    @argfails(
        add_edge!(u, :trophic, :a, :b),
        "Node :b has been removed \
         from this topology."
    )
    @argfails(
        add_edge!(top, :trophic, :a, :b),
        "There is already an edge of type :trophic between nodes :a and :b."
    )
    @argfails(
        remove_node!(u, :x),
        "Invalid node label: :x. \
         Valid labels are :a, :b, :c, :d, :u and :v.",
    )
    @argfails(
        remove_node!(u, :a, :x),
        "Invalid node type label: :x. \
         Valid labels are :nutrients and :species.",
    )
    @argfails(remove_node!(u, :b), "Node :b was already removed from this topology.")
    @argfails(
        remove_node!(u, :b, :species),
        "Node :b was already removed \
         from this topology."
    )
    @argfails(
        remove_node!(top, :b, :nutrients),
        "Invalid :nutrients node label: :b. \
         Valid labels are :u and :v."
    )

    # ======================================================================================
    # Add a whole bunch of edges at once.

    #---------------------------------------------------------------------------------------
    # Within a node compartment.

    w = add_edges_within_node_type!(
        deepcopy(u),
        :species,
        :trophic,
        Bool[
            0 0 1 1
            0 0 0 0
            1 0 0 0
            0 0 1 0
        ],
    )
    #! format: off
    check_display(w,
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
    w = add_edges_within_node_type!(
        deepcopy(u),
        :nutrients,
        :mutualism, # (say)
        Bool[
            0 1
            0 0
        ],
    )
    #! format: off
    check_display(w,
       "Topology(2 node types, 3 edge types, 5 nodes, 4 edges)",
    raw"Topology for 2 node types and 3 edge types with 5 nodes and 4 edges:
  Nodes:
    :species => [:a, :c, :d]  <removed: [:b]>
    :nutrients => [:u, :v]
  Edges:
    :trophic
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
        add_edges_within_node_type!(deepcopy(u), :x, :trophic, e),
        "Invalid node type label: :x. Valid labels are :nutrients and :species."
    )

    @argfails(
        add_edges_within_node_type!(deepcopy(u), :species, :x, e),
        "Invalid edge type label: :x. \
         Valid labels are :interference, :mutualism and :trophic."
    )

    @argfails(
        add_edges_within_node_type!(deepcopy(u), :species, :trophic, e),
        "The given edges matrix should be of size (4, 4) \
         because there are 4 nodes of type :species. \
         Received instead: (0, 0)."
    )

    @argfails(
        add_edges_within_node_type!(
            deepcopy(u),
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
    w = remove_node!(deepcopy(u), :u, :nutrients)
    @argfails(
        add_edges_within_node_type!(
            w,
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
            deepcopy(u),
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
    w = add_edge!(deepcopy(u), :mutualism, :u, :v)
    @argfails(
        add_edges_within_node_type!(
            w,
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

    w = add_edges_accross_node_types!(
        deepcopy(u),
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
    check_display(w,
       "Topology(2 node types, 3 edge types, 5 nodes, 5 edges)",
    raw"Topology for 2 node types and 3 edge types with 5 nodes and 5 edges:
  Nodes:
    :species => [:a, :c, :d]  <removed: [:b]>
    :nutrients => [:u, :v]
  Edges:
    :trophic
      :a => [:v]
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
        add_edges_accross_node_types!(deepcopy(u), :x, :nutrients, :trophic, e),
        "Invalid node type label: :x. Valid labels are :nutrients and :species."
    )

    @argfails(
        add_edges_accross_node_types!(deepcopy(u), :species, :x, :trophic, e),
        "Invalid node type label: :x. Valid labels are :nutrients and :species."
    )

    @argfails(
        add_edges_accross_node_types!(deepcopy(u), :species, :nutrients, :x, e),
        "Invalid edge type label: :x. \
         Valid labels are :interference, :mutualism and :trophic."
    )

    @argfails(
        add_edges_accross_node_types!(deepcopy(u), :species, :species, :trophic, e),
        "Source node types and target node types are the same (:species). \
         Use $add_edges_within_node_type! method instead."
    )

    @argfails(
        add_edges_accross_node_types!(deepcopy(u), :species, :nutrients, :trophic, e),
        "The given edges matrix should be of size (4, 2) \
         because there are 4 nodes of type :species \
         and 2 nodes of type :nutrients. Received instead: (0, 0)."
    )

    # Missing source node.
    @argfails(
        add_edges_accross_node_types!(
            deepcopy(u),
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
    w = remove_node!(deepcopy(u), :u, :nutrients)
    @argfails(
        add_edges_accross_node_types!(
            w,
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
            deepcopy(u),
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
end

end
