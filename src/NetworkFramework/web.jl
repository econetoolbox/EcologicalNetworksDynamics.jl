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
    bpmod =
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

    #---------------------------------------------------------------------------------------
    # From matrix.
    bpmod.eval(
        quote
            mutable struct Matrix <: Blueprint
                A::SparseMatrix{Bool}
                $class::Brought(Class)
                Matrix(A, $class) = new(to_matrix(A), $class)
                Matrix(A; $class = Class) = new(to_matrix(A), $class)
            end
            to_matrix(A) = NF.inputconvert(SparseMatrix{Bool}, A)
            # Infer number of class nodes from matrix size.
            F.implied_blueprint_for(bp::Matrix, ::_Class) =
                $implied_class_from_matrix(d, Class, bp.A)
            F.early_check(bp::Matrix) = $early_check(d, bp.A)
            F.late_check(model, bp::Matrix) = $late_check(d, model, bp.A)
            F.expand!(model, bp::Matrix) = $expand!(d, model, bp.A)
            NF.define_blueprint(Matrix, "boolean matrix of $($w) links")
            export Matrix
        end,
    )

    #---------------------------------------------------------------------------------------
    # From ajacency list.
    bpmod.eval(
        quote
            mutable struct Adjacency <: Blueprint
                A::BinAdjacency
                $class::Brought(Class)
                Adjacency(A, $class = Class) =
                    new(NF.inputconvert(BinAdjacency, A), $class)
            end
            # Infer number or names of class nodes from the lists.
            F.implied_blueprint_for(bp::Adjacency, ::_Class) =
                $implied_class_from_adjacency(d, Class, bp.A)
            F.late_check(model, bp::Adjacency) = $late_check(d, model, bp.A)
            F.expand!(model, bp::Adjacency) = $expand!(d, model, bp.A)
            NF.define_blueprint(Adjacency, "adjacency list of $($w) links")
            export Adjacency
        end,
    )

    # ======================================================================================
    # Component and generic constructors.

    DT = typeof(d)
    Class = D.CamelCasePlural(src)
    comp = mod.eval(quote
        NF.define_component($(Meta.quot(Web)), $mod; blueprints = [$bpmod])
    end)
    C = typeof(comp)
    mod.eval(quote
        $D.component(::$DT) = $C
        (::$_Web)(args...; kwargs...) = $construct($d, $Web, args...; kwargs...)
    end)

    define_web_properties(mod, d; depends = [C])
end

# ==========================================================================================

function define_web_properties(mod::Module, d::EdgeWeb; depends = [])
    web, Web = D.name_variants(d)
    prop, Prop = D.propnames(d)

    w = Meta.quot(web)
    NF.define_propspace(prop)
    defmeth(fn, s) = NF.define_method(fn; depends, read_as = map(s -> :($prop.$s), s))

    M = Symbol(Web, :Methods)
    xp = (
        quote
            module $M
            using EcologicalNetworksDynamics: N, V, D, Network, Model
            const defmeth = $defmeth
            const d = $d

            web(m::Network) = N.web(m, $w)
            topology(m::Network) = web(m).topology
            number(m::Network) = m |> topology |> N.n_edges
            mask(::Network, m::Model) = V.edges_mask_view(m, d)

            defmeth(topology, [:_topology])
            defmeth(mask, [:mask, :matrix])
            defmeth(number, [:n_links, :n_edges])
            end
        end
    ).args |> last

    mod.eval(xp)
end

# ==========================================================================================
# Extract implementation detail to ease Revise work.

#-------------------------------------------------------------------------------------------
# Construct.

construct(::EdgeWeb, Web::Component, A, args...; kwargs...) = input_try(
    A,
    SparseMatrix{Bool} => A -> Web.Matrix(A, args...; kwargs...),
    BinAdjacency => (A -> Web.Adjacency(A, args...; kwargs...), rethrow),
)

#-------------------------------------------------------------------------------------------
# Early check.

function early_check(::EdgeWeb, A::AbstractMatrix)
    n, m = size(A)
    n == m || F.checkfails("The adjacency matrix of size $((m, n)) is not squared.")
end

#-------------------------------------------------------------------------------------------
# Late check.

function late_check(d::EdgeWeb, m::Model, A::SparseMatrix{Bool})
    a, b = size(A)
    src = D.source(d)
    class = D.snake_case_singular(src)
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
    check_refs(d, adj) do side, lab
        N.is_label(index, lab) ||
            F.checkfails("Not a $side label among $(repr(class)): $(repr(lab))")
    end
end

function late_check(d::EdgeWeb, m::Model, adj::BinAdjacency{Int})
    class = D.sourcename(d)
    index = getproperty(m, class)._index
    n = length(index)
    check_refs(d, adj) do side, i
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
# Implied class blueprint.

function implied_class_from_matrix(::EdgeWeb, Class, A)
    n = size(A, 1)
    Class.Number(n)
end

function implied_class_from_adjacency(::EdgeWeb, Class, adj::BinAdjacency{Symbol})
    refs = NF.all_refs(adj)
    Class.Names(collect(refs))
end

function implied_class_from_adjacency(::EdgeWeb, Class, adj::BinAdjacency{Int})
    refs = NF.all_refs(adj)
    Class.Number(last(refs))
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
        (to_i(src), I.map(to_i, sub))
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
