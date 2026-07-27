"""
Expand into a new reflexive web from a sparse boolean matrix.
"""
abstract type ReflexiveWebMatrixBlueprint <: Blueprint end

"""
Expand into a new reflexive web from an adjacency list.
"""
abstract type ReflexiveWebAdjacencyBlueprint <: Blueprint end

"""
Typical setup for a component bringing a new reflexive web to the network.
"""
function define_reflexive_web_component(mod::Module, d::D.Web)
    # TODO: have it generic over D.is_sparse(d) the day it's required.

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
    bpmod = mod.eval(
        (
            quote
                module $Web_
                import EcologicalNetworksDynamics: F, NF, SparseMatrix, BinAdjacency, Model
                const d = $d
                const src = $src
                const Class = $(D.component(src))
                const _Class = typeof(Class)
                end
            end
        ).args |> last,
    )

    #---------------------------------------------------------------------------------------
    # From matrix.
    bpmod.eval(
        quote
            mutable struct Matrix <: NF.ReflexiveWebMatrixBlueprint
                A::SparseMatrix{Bool}
                Matrix(A) = new(NF.inputconvert(SparseMatrix{Bool}, A))
            end
            # Infer number of class nodes from matrix size.
            F.implied(::Matrix) = (Class,)
            F.implied_blueprint_for(bp::Matrix, ::Type{_Class}) =
                NF.implied_class(d, Class, bp)
            F.early_check(bp::Matrix) = NF.early_check(d, bp)
            F.late_check(model, bp::Matrix) = NF.late_check(d, model, bp)
            F.expand!(model, bp::Matrix) = NF.expand!(d, model, bp)
            NF.define_blueprint(Matrix, "boolean matrix of $($w) links")
            export Matrix
        end,
    )

    #---------------------------------------------------------------------------------------
    # From ajacency list.
    bpmod.eval(
        quote
            mutable struct Adjacency <: NF.ReflexiveWebAdjacencyBlueprint
                A::BinAdjacency
                Adjacency(A) = new(NF.inputconvert(BinAdjacency, A))
            end
            # Infer number or names of class nodes from the lists.
            F.implied(::Adjacency) = (Class,)
            F.implied_blueprint_for(bp::Adjacency, ::Type{_Class}) =
                NF.implied_class(d, Class, bp)
            F.late_check(model, bp::Adjacency) = NF.late_check(d, model, bp)
            F.expand!(model, bp::Adjacency) = NF.expand!(d, model, bp)
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
        $D.component(::$DT) = $comp
        (::$_Web)(args...; kwargs...) = NF.construct($d, $Web, args...; kwargs...)
    end)

    define_web_properties(mod, d; depends = [C])
    comp
end

# ==========================================================================================

function define_web_properties(mod::Module, d::D.Web; depends = [])
    web, Web = D.name_variants(d)
    prop, Prop = D.propnames(d)

    NF.define_propspace(prop)
    defmeth(fn, s) = NF.define_method(fn; depends, read_as = map(s -> :($prop.$s), s))

    M = Symbol(Web, :Methods)
    mod.eval((
        quote
            module $M
            using EcologicalNetworksDynamics: N, V, D, Network, Model
            const defmeth = $defmeth
            const d = $d
            const w = D.web(d)

            web(m::Network) = N.web(m, w)
            topology(m::Network) = web(m).topology
            number(m::Network) = m |> topology |> N.n_edges
            mask(::Network, m::Model) = V.mask_view(d, m)

            defmeth(topology, [:_topology])
            defmeth(mask, [:mask, :matrix])
            defmeth(number, [:n_links, :n_edges])
            end
        end
    ).args |> last)
end

# ==========================================================================================
# Extract implementation detail to ease Revise work.

#-------------------------------------------------------------------------------------------
# Construct.

construct(::D.Web, Web::Component, input, args...; kwargs...) = try_convert(
    input,
    SparseMatrix{Bool} => A -> Web.Matrix(A, args...; kwargs...),
    BinAdjacency => A -> Web.Adjacency(A, args...; kwargs...),
)

#-------------------------------------------------------------------------------------------
# Early check.

function early_check(::D.Web, bp::ReflexiveWebMatrixBlueprint)
    (; A) = bp
    n, m = size(A)
    n == m || checkerr(A, "The adjacency matrix of size $((m, n)) is not squared.")
end

#-------------------------------------------------------------------------------------------
# Late check.

function late_check(d::D.Web, m::Model, bp::ReflexiveWebMatrixBlueprint)
    (; A) = bp
    a, b = size(A)
    src = D.source(d)
    class = D.snake_case_singular(src)
    n = getproperty(m, class).number
    if !(n == a == b)
        src = D.sourcename(d)
        (are, s) = n == 1 ? ("is", "") : ("are", "s")
        checkerr(
            A,
            "There $are $n $(repr(src)) node$s \
             but the provided matrix is of size ($a, $b).",
        )
    end
end

# Dispatch over either label or indices refs.
late_check(d::D.Web, m::Model, bp::ReflexiveWebAdjacencyBlueprint) = late_check(d, m, bp.A)

function late_check(d::D.Web, m::Model, adj::BinAdjacency{Symbol})
    class = D.sourcename(d)
    index = getproperty(m, class)._index
    check_refs(d, adj) do side, lab
        N.is_label(index, lab) ||
            checkerr(adj, "Not a $side label among $(repr(class)): $(repr(lab))")
    end
end

function late_check(d::D.Web, m::Model, adj::BinAdjacency{Int})
    class = D.sourcename(d)
    index = getproperty(m, class)._index
    n = length(index)
    check_refs(d, adj) do side, i
        N.is_index(index, i) ||
            checkerr(adj, "Not a valid $side $(repr(class)) index among $n nodes: [$i].")
    end
end

function check_refs(check, ::D.Web, adj::BinAdjacency)
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

function implied_class(::D.Web, Class, bp::ReflexiveWebMatrixBlueprint)
    (; A) = bp
    n = size(A, 1)
    Class.Number(n)
end

implied_class(d::D.Web, Class, bp::ReflexiveWebAdjacencyBlueprint) =
    implied_class(d, Class, bp.A) # Dispatch over ref type: indices or labels.

function implied_class(::D.Web, Class, adj::BinAdjacency{Symbol})
    refs = NF.all_refs(adj)
    Class.Names(collect(refs))
end

function implied_class(::D.Web, Class, adj::BinAdjacency{Int})
    refs = NF.all_refs(adj)
    Class.Number(last(refs))
end

#-------------------------------------------------------------------------------------------
# Expand.

expand!(d::D.Web, model, bp::ReflexiveWebMatrixBlueprint) =
    expand!(d, model, N.SparseReflexive(bp.A))

function expand!(d::D.Web, model, bp::ReflexiveWebAdjacencyBlueprint)
    adj = bp.A
    class = D.sourcename(d)
    index = getproperty(model, class)._index
    to_i(label) = N.to_index(index, label)
    topology = N.SparseReflexive(length(index), I.map(adj) do (src, sub)
        (to_i(src), I.map(to_i, sub))
    end)
    expand!(d, model, topology)
end

function expand!(d::D.Web, md::Model, top::Topology)
    c = D.sourcename(d)
    w = D.web(d)
    network = NF.network(md)
    N.add_web!(network, w, (c, c), top)
    post_expand!(d, md)
end

# Extension point.
post_expand!(::D.Web, model) = nothing
