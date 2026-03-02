"""
Typical setup for a component bringing a new reflexive web to the network.
"""
function define_reflexive_web_component(mod::Module, d::EdgeWeb)

    prop, Prop = D.propnames(d)
    web, Web = D.name_variants(d)
    class, same = D.sidenames(d)
    same == class || argerr("Reflexive webs must match source and target, \
                             here $(repr(class)) != $(repr(same)).")
    src = D.source(d)
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
                        SparseMatrix,
                        N,
                        Network,
                        F,
                        Brought,
                        Blueprint,
                        @blueprint,
                        NF,
                        BinAdjacency,
                        Model
                    const d = $d
                    const src = $src
                    const Class = $(D.component(src))
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
            F.late_check(_, bp::Matrix, model) = $late_check(d, bp.A, model)
            F.expand!(model, bp::Matrix, _) = $expand!(d, model, bp.A)
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
            F.early_check(bp::Adjacency) = $early_check(d, bp.A)
            F.late_check(model, bp::Adjacency, data) = $late_check(d, model, data)
            F.expand!(model, bp::Adjacency, _) = $expand!(d, model, bp.A)
            @blueprint Adjacency "adjacency list of $($w) links"
            export Adjacency
        end,
    )

    # ======================================================================================
    # Component and generic constructors.

    DT = typeof(d)
    Class = D.CamelCasePlural(src)
    mod.eval(quote
        @component $Web{Network} requires($Class) blueprints($Web_)
        $D.component(::$DT) = $Web
        (::$_Web)(A) = $construct($d, $Web, A)
    end)

    define_web_properties(mod, d, :(depends($Web)))
end

# ==========================================================================================

function define_web_properties(
    mod::Module,
    d::EdgeWeb,
    deps::Expr, # As in a regular call to @method.
)
    web, Web = D.name_variants(d)
    prop, Prop = D.propnames(d)
    w = Meta.quot(web)
    M = Symbol(Web, :Methods) # Create submodule to not pollute invocation scope..
    m = :(mod($mod)) # .. but still evaluate dependencies within the invocation module.
    xp = quote

        @propspace $prop

        module $M
        import EcologicalNetworksDynamics: N, Network, Model, Views, @method

        web(m::Network) = Networks.web(m, $w)
        topology(m::Network) = web(m).topology
        number(m::Network) = m |> topology |> n_edges
        mask(::Network, m::Model) = Views.edges_mask_view(m, $w)
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

function early_check(d::EdgeWeb, A)
    try
        # Re-parse in case the blueprint was mutated prior to expansion.
        parse(Adjacency, A)
    catch e
        e isa InputError || rethrow(e)
        F.checkfails("When early checking adjacency-list for $d:\n$(e.mess)", rethrow)
    end
end

#-------------------------------------------------------------------------------------------
# Late check.

function late_check(d::EdgeWeb, m::Model, A::SparseMatrix{Bool})
    a, b = size(A)
    src = D.source(d)
    class = D.snake_case_singular()
    n = getproperty(m, class).number
    if !(n == a == b)
        src = D.sourcename(d)
        (are, s) = n == 1 ? ("is", "") : ("are", "s")
        F.checkfails("There $are $n $(repr(src)) node$s \
                      but the provided matrix is of size ($a, $b).")
    end
end

function late_check(d::EdgeWeb, m::Model, adj::BinAdjacency{Symbol})
    class = D.sourcename(d)
    index = getproperty(m, class)._index
    check_refs(adj) do (side, lab)
        N.is_label(index, lab) ||
            F.checkfails("Not a $side label among $(repr(class)): $(repr(lab))")
    end
end

function late_check(d::EdgeWeb, m::Model, adj::BinAdjacency{Int})
    class = D.sourcename(d)
    index = getproperty(m, class)._index
    n = length(index)
    check_refs(d, adj) do (side, i)
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

expand!(d::EdgeWeb, model, matrix::SparseMatrix{Bool}) =
    expand!(d, model, N.SparseReflexive(matrix))

function expand!(d::EdgeWeb, model, adj)
    class = D.sourcename(d)
    index = getproperty(model, class)._index
    to_i(label) = N.to_index(index, label)
    topology = N.SparseReflexive(length(index), I.map(adj) do (src, sub)
        (to_i(sub), I.map(to_i, sub))
    end)
    expand!(d, model, topology)
end

function expand!(d::EdgeWeb, md::Model, top::Topology)
    c = D.sourcename(d)
    w = D.web(d)
    network = NF.network(md)
    N.add_web!(network, w, (c, c), top)
    post_expand!(d, md)
end

# Possible extension point.
post_expand!(::EdgeWeb, model) = nothing
