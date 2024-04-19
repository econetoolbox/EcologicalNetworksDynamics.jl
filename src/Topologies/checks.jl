# Raise errors on invalid input, useful to check exposed queries.

G = Topology
#-------------------------------------------------------------------------------------------
# Check indices validity.

has_index(i, n) = 1 <= i <= n
err_index(i, n, what) = argerr("Invalid $what index ($i) \
                                when there $(n > 1 ? "are" : "is") $n $what$(s(n)).")
function check_index(i, n, what)
    has_index(i, n) || err_index(i, n, what isa String ? what : what())
    i
end

has_node_type(g::G, i::Int) = has_index(i, length(g.node_types_labels))
check_node_type(g::G, i::Int) = check_index(i, length(g.node_types_labels), "node type")

has_edge_type(g::G, i::Int) = has_index(i, length(g.edge_types_labels))
check_edge_type(g::G, i::Int) = check_index(i, length(g.edge_types_labels), "edge type")

has_node_ref(g::G, i::Abs) = has_index(i.abs, length(g.nodes_labels))
check_node_ref(g::G, i::Abs) = check_index(i.abs, length(g.nodes_labels), "node")

# Check relative indices ASSUMING the node type is valid.
has_node_ref(g::G, i::Rel, type::IRef) =
    has_index(i.rel, U.n_nodes_including_removed(g, type))
check_node_ref(g::G, i::Rel, type::IRef) = check_index(
    i.rel,
    U.n_nodes_including_removed(g, type),
    () -> "$(repr(U.node_type_label(g, type))) node",
)

#-------------------------------------------------------------------------------------------
# Check labels validity.

has_label(lab, set) = lab in set
function err_label(lab, set, what)
    valid = if isempty(set)
        "There are no labels in this topology yet."
    else
        "Valid labels within this topology are $(join(sort(repr.(set)), ", ", " and "))."
    end
    argerr("Invalid $what label: $(repr(lab)). $valid")
end
function check_label(lab, set, what)
    has_label(lab, set) || err_label(lab, set, what isa String ? what : what())
    lab
end

has_node_type(g::G, lab::Symbol) = has_label(lab, keys(g.node_types_index))
check_node_type(g::G, lab::Symbol) = check_label(lab, keys(g.node_types_index), "node type")

has_edge_type(g::G, lab::Symbol) = has_label(lab, keys(g.edge_types_index))
check_edge_type(g::G, lab::Symbol) = check_label(lab, keys(g.edge_types_index), "edge type")

has_node_ref(g::G, lab::Symbol) = has_label(lab, keys(g.nodes_index))
check_node_ref(g::G, lab::Symbol) = check_label(lab, keys(g.nodes_index), "node")

# Check "relative labels" ASSUMING the node type is valid.
has_node_ref(g::G, lab::Symbol, type::IRef) = has_label(lab, U._node_labels(g, type))
check_node_ref(g::G, lab::Symbol, type::IRef) = check_label(
    lab,
    U._nodes_labels(g, type),
    () -> "$(repr(U.node_type_label(g, type))) node",
)

#-------------------------------------------------------------------------------------------
# Check node liveliness, assuming the reference is valid.

function check_live_node(g::G, node::AbsRef, original_ref::AbsRef = node)
    # (use the original reference to trace back to actual user input
    # and improve error message)
    U.is_removed(g, node) &&
        argerr("Node $(repr(original_ref)) has been removed from this topology.")
    node
end

#-------------------------------------------------------------------------------------------
# Check node labels availability.

function check_new_nodes_labels(g::G, labels::Vector{Symbol})
    for new_lab in labels
        if has_node_ref(g, new_lab)
            argerr("Label :$new_lab was already given \
                    to a node of type \
                    $(repr(U.type_of_node(g, new_lab))).")
        end
    end
    labels
end

function check_new_nodes_labels(g::G, labels)
    try
        labels = Symbol[Symbol(l) for l in labels]
    catch
        argerr("The labels provided cannot be iterated into a collection of symbols. \
                Received: $(repr(labels)).")
    end
    check_new_nodes_labels(g, labels)
end
