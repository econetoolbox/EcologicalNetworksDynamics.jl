"""
Typical setup for a component bringing a new reflexive web to the network.
"""
function define_reflexive_web_component(mod::Module, ew::EdgeWeb)

    prop, Prop = D.propnames(ew)
    web, Web = D.name_variants(ew)
    class, same = D.sidenames(ew)
    same == class || argerr("Reflexive webs must match source and target, \
                             here $(repr(class)) != $(repr(same)).")
    nc = D.source(ew)
    Web_ = Symbol(Web, :_) # Blueprints module name.
    _Web = Symbol(:_, Web) # Component type name.
    w, c, p = Meta.quot.((web, class, prop)) # Symbol names.

    # ======================================================================================
    # Blueprints for the component.

    # Prepare dedicated blueprints module and populate namespace.
    blueprints =
        mod.eval.(
            (
                quote
                    module $Web_
                    import EcologicalNetworksDynamics:
                        Blueprint,
                        Framework,
                        Networks,
                        @blueprint,
                        NetworkConfig,
                        NetworkFramework
                    using .Network
                    using .Framework
                    using .NetworkFramework
                    const F = Framework
                    const N = Network
                    const NF = NetworkFramework
                    const ew = $ew
                    const nc = $nc
                    const Class = $(C.component(nc))
                    const _Class = typeof(Class)
                    end
                end
            ).args
        ) |> last

    # From matrix.
    blueprints.eval(
        quote
            mutable struct Matrix <: Blueprint
                A::SparseMatrix{Bool}
                $class::Brought(Class)
                Matrix(A, $class = Class) =
                    new(inputconvert(SparseMatrix{Bool}, A), $class)
            end
            # Infer number of class nodes from matrix size.
            F.implied_blueprint_for(bp::Matrix, ::_Class) = Class(size(bp.A, 1))
            F.early_check(bp::Matrix) = $early_check(bp.A)
            F.late_check(_, bp::Matrix, model) = $late_check(ew, bp.A, model)
            F.expand!(model, bp::Matrix, _) = $expand!(ew, model, bp.A)
            @blueprint Matrix "boolean matrix of $($w) links"
            export Matrix
        end,
    )

    # From ajacency list.
    blueprints.eval(
        quote
            mutable struct Adjacency <: Blueprint
                A::BinAdjacency
                $class::Brought(Class)
                Adjacency(A, $class = Class) = new(parse(BinAdjacency, A), $class)
            end
            # Infer number or names of class nodes from the lists.
            F.implied_blueprint_for(bp::Adjacency, ::_Class) = Class(refspace(bp.A))
            F.early_check(bp::Adjacency) = $early_check(ew, bp.A)
            F.late_check(model, bp::Adjacency, data) = $late_check(ew, model, data)
            F.expand!(model, bp::Adjacency, _) = $expand!(ew, model, bp.A)
            @blueprint Adjacency "adjacency list of $($w) links"
            export Adjacency
        end,
    )

    # ======================================================================================
    # Component and generic constructors.

    EW = typeof(ew)
    Class = D.CamelCasePlural(nc)
    mod.eval(quote
        @component $Web{Network} requires($Class) blueprints($Web_)
        C.component(::$EW) = $Web
        (::$_Web)(A) = $construct($ew, $Web, A)
    end)

    define_web_properties(mod, ew, :(depends($Web)))
end

# ==========================================================================================

function define_web_properties(
    mod::Module,
    ew::EdgeWeb,
    deps::Expr, # As in a regular call to @method.
)
    web, Web = D.name_variants(ew)
    prop, Prop = D.propnames(ew)
    w = Meta.quot(web)
    M = Symbol(Web, :Methods) # Create submodule to not pollute invocation scope..
    m = :(mod($mod)) # .. but still evaluate dependencies within the invocation module.
    xp = quote

        @propspace $prop

        module $M
        import EcologicalNetworksDynamics: Model, Networks, Network, Framework, Views
        using .Networks
        using .Framework
        using .Views

        web(m::Network) = Networks.web(m, $w)
        topology(m::Network) = web(m).topology
        number(m::Network) = m |> topology |> n_edges
        mask(::Network, m::Model) = edges_mask_view(m, $w)
        @method $m $M.topology $deps read_as($prop._topology)
        @method $m $M.mask $deps read_as($prop.matrix, $prop.mask)
        @method $m $M.number $deps read_as($prop.n_links, $prop.n_edges)

        end
    end

    mod.eval.(xp.args)
end

# ==========================================================================================
# Extract implementation detail to ease Revise work.

#-------------------------------------------------------------------------------------------
# Construct.

construct(::EdgeWeb, Web::Component, A) =
    input_try(A, SparseMatrix => Web.Matrix, Adjacency => Web.Adjacency)

#-------------------------------------------------------------------------------------------
# Early check.

function early_check(::EdgeWeb, A::AbstractMatrix)
    n, m = size(A)
    n == m || F.checkfails("The adjacency matrix of size $((m, n)) is not squared.")
end

function early_check(ew::EdgeWeb, A)
    try
        # Re-parse in case the blueprint was mutated prior to expansion.
        parse(Adjacency, A)
    catch e
        e isa InputError || rethrow(e)
        F.checkfails("When early checking adjacency-list for $ew:\n$(e.mess)", rethrow)
    end
end

#-------------------------------------------------------------------------------------------
# Late check.

function late_check(ew::EdgeWeb, m::Model, A::SparseMatrix{Bool})
    a, b = size(A)
    src = D.source(ew)
    class = D.snake_case_singular()
    n = getproperty(m, class).number
    if !(n == a == b)
        src = D.sourcename(ew)
        (are, s) = n == 1 ? ("is", "") : ("are", "s")
        F.checkfails("There $are $n $(repr(src)) node$s \
                      but the provided matrix is of size ($a, $b).")
    end
end

function late_check(ew::EdgeWeb, m::Model, adj::BinAdjacency{Symbol})
    class = D.sourcename(ew)
    index = getproperty(m, class)._index
    check_refs(adj) do (side, lab)
        N.is_label(index, lab) ||
            F.checkfails("Not a $side label among $(repr(class)): $(repr(lab))")
    end
end

function late_check(ew::EdgeWeb, m::Model, adj::BinAdjacency{Int})
    class = D.sourcename(ew)
    index = getproperty(m, class)._index
    n = length(index)
    check_refs(ew, adj) do (side, i)
        N.is_index(index, i) ||
            F.checkfails("Not a valid $side $(repr(class)) index among $n nodes: [$i].")
    end
end

function check_refs(check, ::EdgeWeb, adj::BinAdjacency)
    for (src, sub) in adj
        check("source", src)
        for tgt in sub
            check("target", tgt)
        end
    end
    adj
end

#-------------------------------------------------------------------------------------------
# Expand.

expand!(ew::EdgeWeb, model, matrix::SparseMatrix{Bool}) =
    expand!(ew, model, N.SparseReflexive(matrix))

function expand!(ew::EdgeWeb, model, adj)
    class = D.sourcename(ew)
    index = getproperty(model, class)._index
    to_i(label) = N.to_index(index, label)
    topology = N.SparseReflexive(length(index), I.map(adj) do (src, sub)
        (to_i(sub), I.map(to_i, sub))
    end)
    expand!(ew, model, topology)
end

function expand!(ew::EdgeWeb, md::Model, top::Topology)
    c = D.sourcename(ew)
    w = D.web(ew)
    network = NF.network(md)
    N.add_web!(network, w, (c, c), top)
    post_expand!(ew, md)
end

# Possible extension point.
post_expand!(::EdgeWeb, model) = nothing
