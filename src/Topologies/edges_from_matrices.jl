# Add a bunch of edges from a square matrix input corresponding to one node compartment.
# The matrix size must match the total number of nodes in this compartment,
# *including* (blank) removed nodes.
function add_edges_within_node_type!(
    top::Topology,
    node_type::IRef,
    edge_type::IRef,
    e::AbstractSparseMatrix{Bool},
)
    # Check transaction.
    check_node_type(top, node_type)
    check_edge_type(top, edge_type)
    i_edge_type = U.edge_type_index(top, edge_type)
    indices = U._nodes_abs_range(top, node_type)
    n = length(indices)
    size(e) == (n, n) || argerr("The given edges matrix should be of size ($n, $n) \
                                 because there $(are(n)) $n node$(s(n)) \
                                 of type $(repr(U.node_type_label(top, node_type))). \
                                 Received instead: $(size(e)).")
    # (matrix indices start from 1, not all node indices)
    offset = U.node_index_offset(top, node_type)
    sources, targets, _ = findnz(e)
    sources .+= offset
    targets .+= offset

    # Check that no edge would point to a removed node.
    for (indices, dim) in ((sources, "row"), (targets, "column"))
        for i_node in indices
            a_n = Abs(i_node)
            if U.is_removed(top, a_n)
                i_matrix = i_node - offset
                # Clarify error in case the offset is relevant.
                par = if offset == 0
                    " (index $i_node)"
                else
                    " (index $i_node: $(th(i_matrix)) \
                       within the $(repr(U.node_type_label(top, node_type))) node type)"
                end
                argerr("Node $(repr(U.node_label(top, a_n)))$par \
                        has been removed from this topology, \
                        but the given matrix has a nonzero entry in \
                        $dim $(i_matrix).")
            end
        end
    end

    # Check that no edge already exists within the topology.
    for (i_src, i_tgt) in zip(sources, targets)
        a_s = Abs(i_src)
        a_t = Abs(i_tgt)
        if U.has_edge(top, i_edge_type, a_s, a_t)
            etype = U.edge_type_label(top, i_edge_type)
            src = U.node_label(top, a_s)
            tgt = U.node_label(top, a_t)
            i_matrix = i_src - offset
            j_matrix = i_tgt - offset
            par = if offset == 0
                " (indices $i_src and $i_tgt)"
            else
                " (indices $i_src and $i_tgt: \
                 resp. $(th(i_matrix)) and $(th(j_matrix)) \
                 within node type $(repr(U.node_type_label(top, node_type))))"
            end
            argerr("There is already an edge of type $(repr(etype)) \
                    between nodes $(repr(src)) and $(repr(tgt))$par, \
                    but the given matrix has a nonzero entry in \
                    ($i_matrix, $j_matrix).")
        end
    end

    # Commit.
    for (i_src, i_tgt) in zip(sources, targets)
        _add_edge!(top, i_edge_type, Abs(i_src), Abs(i_tgt))
    end

    top
end
add_edges_within_node_type!(top::Topology, n::IRef, e::IRef, m::Matrix{Bool}) =
    add_edges_within_node_type!(top, n, e, sparse(m))
export add_edges_within_node_type!

# ==========================================================================================
# Same logic, but *accross* two node types.
# (mostly duplicated from above)

function add_edges_accross_node_types!(
    top::Topology,
    source_node_type::IRef,
    target_node_type::IRef,
    edge_type::IRef,
    e::AbstractSparseMatrix{Bool},
)
    # Check transaction.
    check_node_type(top, source_node_type)
    check_node_type(top, target_node_type)
    check_edge_type(top, edge_type)
    i_edge_type = U.edge_type_index(top, edge_type)
    source_indices = U._nodes_abs_range(top, source_node_type)
    target_indices = U._nodes_abs_range(top, target_node_type)
    source_indices == target_indices && argerr("Source node types and target node types \
                                                are the same ($(repr(source_node_type))). \
                                                Use $add_edges_within_node_type! \
                                                method instead.")
    n = length(source_indices)
    m = length(target_indices)
    size(e) == (n, m) || argerr("The given edges matrix should be of size ($n, $m) \
                                 because there $(are(n)) $n node$(s(n)) of type \
                                 $(repr(U.node_type_label(top, source_node_type))) \
                                 and $m node$(s(m)) of type \
                                 $(repr(U.node_type_label(top, target_node_type))). \
                                 Received instead: $(size(e)).")
    # (matrix indices start from 1, not all node indices)
    source_offset = U.node_index_offset(top, source_node_type)
    target_offset = U.node_index_offset(top, target_node_type)
    sources, targets, _ = findnz(e)
    sources .+= source_offset
    targets .+= target_offset

    # Check that no edge would point to a removed node.
    for (indices, dim, offset, node_type) in (
        (sources, "row", source_offset, source_node_type),
        (targets, "column", target_offset, target_node_type),
    )
        for i_node in indices
            a_n = Abs(i_node)
            if U.is_removed(top, a_n)
                i_matrix = i_node - offset
                # Clarify error in case the offset is relevant.
                par = if offset == 0
                    ""
                else
                    " (index $i_node: $(th(i_matrix)) \
                       within the $(repr(U.node_type_label(top, node_type))) node type)"
                end
                argerr("Node $(repr(U.node_label(top, a_n)))$par \
                        has been removed from this topology, \
                        but the given matrix has a nonzero entry in \
                        $dim $(i_matrix).")
            end
        end
    end

    # Check that no edge already exists within the topology.
    for (i_src, i_tgt) in zip(sources, targets)
        a_s = Abs(i_src)
        a_t = Abs(i_tgt)
        if U.has_edge(top, i_edge_type, a_s, a_t)
            etype = U.edge_type_label(top, i_edge_type)
            src = U.node_label(top, a_s)
            tgt = U.node_label(top, a_t)
            i_matrix = i_src - source_offset
            j_matrix = i_tgt - target_offset
            par = " (indices $i_src and $i_tgt: \
                   resp. $(th(i_matrix)) and $(th(j_matrix)) \
                   within node types $(repr(U.node_type_label(top, source_node_type))) \
                                 and $(repr(U.node_type_label(top, target_node_type))))"
            argerr("There is already an edge of type $(repr(etype)) \
                    between nodes $(repr(src)) and $(repr(tgt))$par, \
                    but the given matrix has a nonzero entry in \
                    ($i_matrix, $j_matrix).")
        end
    end

    # Commit.
    for (i_src, i_tgt) in zip(sources, targets)
        _add_edge!(top, i_edge_type, Abs(i_src), Abs(i_tgt))
    end

    top
end
add_edges_accross_node_types!(top::Topology, n::IRef, m::IRef, t::IRef, e::Matrix{Bool}) =
    add_edges_accross_node_types!(top, n, m, t, sparse(e))
export add_edges_accross_node_types!
