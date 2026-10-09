"Expand into a new edges web."
abstract type WebBlueprint <: Blueprint end

"""
Expand into a new reflexive web from a sparse boolean matrix.
"""
abstract type ReflexiveWebMatrixBlueprint <: WebBlueprint end

"""
Expand into a new reflexive web from an adjacency list.
"""
abstract type ReflexiveWebAdjacencyBlueprint <: WebBlueprint end

"""
Typical setup for a component bringing a new reflexive web to the network.
"""
function define_reflexive_web_component(mod::Module, d::D.Web)
    # TODO: have it generic over D.is_sparse(d) the day it's required.

    _D = typeof(d)
    prop, Prop = D.propnames(d)
    src, _ = D.source(d)
    Class = D.component(src)

    web, Web = D.name_variants(d)
    class, same = D.sidenames(d)
    same == class || argerr("Reflexive webs must match source and target, \
                             here $(repr(class)) != $(repr(same)).")
    Web_ = Symbol(Web, :_) # Blueprints module name.
    _Web = Symbol(:_, Web) # Component type name.
    w = Meta.quot(web) # Symbol names.

    # ======================================================================================
    # Blueprints for the component.

    # Prepare dedicated blueprints module and populate namespace.
    bpmod = mod.eval(
        (
            quote
                module $Web_
                using EcologicalNetworksDynamics.NetworkFramework:
                    F, NF, SparseMatrix, BinAdjacency, Model, @bp_construct
                const d, src, Class = $d, $src, $Class
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
                @bp_construct Matrix
            end
            export Matrix
            NF.register_blueprint(Matrix, "boolean matrix of $($w) links"; d,
                implied = (Class,), # Infer number of class nodes from matrix size.
            )
        end,
    )

    #---------------------------------------------------------------------------------------
    # From ajacency list.
    bpmod.eval(
        quote
            mutable struct Adjacency <: NF.ReflexiveWebAdjacencyBlueprint
                A::BinAdjacency
                @bp_construct Adjacency
            end
            export Adjacency
            NF.register_blueprint(Adjacency, "adjacency list of $($w) links"; d,
                implied = (Class,), # Infer number or names of class nodes from the lists.
            )
        end,
    )

    # ======================================================================================
    # Component and generic constructors.

    c = NF.eval(
        quote
            define_component(
                $(Meta.quot(Web)),
                $mod;
                requires = ($Class,),
                blueprints = ($bpmod,),
            )
        end,
    )
    C = typeof(c)
    NF.eval(quote
        $D.component(::$_D) = $c
        (::$C)(args...; kwargs...) = NF.construct($d, $c, args...; kwargs...)
    end)

    define_web_properties(mod, d; depends = (C,))
    c
end

# ==========================================================================================

function define_web_properties(mod::Module, d::D.Web; depends = ())
    w = D.web(d)
    web, Web = D.name_variants(d)
    prop, Prop = D.propnames(d)

    NF.define_propspace(prop)
    NF.define_propspace(:($prop.iter))
    NF.define_propspace(:($prop.iter.index))
    NF.define_propspace(:($prop.iter.label))
    defmeth(fn, s) =
        NF.define_method(fn; depends, read_as = map(s -> paste_paths(prop, s), s))

    M = Symbol(Web, :Methods)
    mod.eval(
        (
            quote
                module $M
                using EcologicalNetworksDynamics.NetworkFramework:
                    I, N, V, D, Network, Model
                const d, defmeth, w = $d, $defmeth, $(Meta.quot(w))

                web(n::Network) = N.web(n, w)
                topology(n::Network) = web(n).topology
                number(n::Network) = n |> topology |> N.n_edges
                mask(::Network, m::Model) = V.mask_view(d, m)

                defmeth(topology, [:_topology])
                defmeth(mask, [:mask, :matrix])
                defmeth(number, [:n_links, :n_edges])

                #---------------------------------------------------------------------------
                # Edges iterators.

                edges(n::Network) = n |> topology |> N.edges
                forward(n::Network) = n |> topology |> N.forward
                backward(n::Network) = n |> topology |> N.backward

                # Variants: reverse or skip empty subgroups.
                edges_transposed(n::Network) = n |> topology |> N.edges_transposed
                forward_skip(n::Network) = N.forward(topology(n), skip = true)
                backward_skip(n::Network) = N.backward(topology(n), skip = true)

                # Produce labeled variants.
                function labeled_flat(fn::Function)
                    function labeled(n::Network)
                        index = N.source(n, w).index
                        I.map(fn(n)) do (i, j)
                            N.to_label.((index,), (i, j))
                        end
                    end
                end
                function labeled_nested(fn::Function)
                    function labeled(n::Network)
                        index = N.source(n, w).index
                        I.map(fn(n)) do (i, sub)
                            (N.to_label(index, i), I.map(sub) do (j, e)
                                (N.to_label(index, j), e)
                            end)
                        end
                    end
                end

                # Raw index iterators.
                defmeth(edges, [:(iter.index.edges)])
                defmeth(edges_transposed, [:(iter.index.edges_transposed)])
                defmeth(forward, [:(iter.index.forward)])
                defmeth(backward, [:(iter.index.backward)])
                defmeth(forward_skip, [:(iter.index.forward_skip)])
                defmeth(backward_skip, [:(iter.index.backward_skip)])

                # Yet default to labeled output.
                defmeth(labeled_flat(edges), [:(iter.edges), :(iter.label.edges)])
                defmeth(
                    labeled_flat(edges_transposed),
                    [:(iter.edges_transposed), :(iter.label.edges_transposed)],
                )
                defmeth(labeled_nested(forward), [:(iter.forward), :(iter.label.forward)])
                defmeth(
                    labeled_nested(backward),
                    [:(iter.backward), :(iter.label.backward)],
                )
                defmeth(
                    labeled_nested(forward_skip),
                    [:(iter.forward_skip), :(iter.label.forward_skip)],
                )
                defmeth(
                    labeled_nested(backward_skip),
                    [:(iter.backward_skip); :(iter.label.backward_skip)],
                )

                end
            end
        ).args |> last,
    )
end

# ==========================================================================================
# Specialization.

data(bp::WebBlueprint) = bp.A
datatype(::Type{<:ReflexiveWebMatrixBlueprint}) = SparseMatrix{Bool}
datatype(::Type{<:ReflexiveWebAdjacencyBlueprint}) = BinAdjacency

#-------------------------------------------------------------------------------------------
# Construct.

# Pick blueprint depending on input conversion success.
function construct(::D.Web, Web::Component, input, args...; kwargs...)
    try_convert(
        input,
        SparseMatrix{Bool} => A -> Web.Matrix(A, args...; kwargs...),
        BinAdjacency => A -> Web.Adjacency(A, args...; kwargs...),
    )
end

#-------------------------------------------------------------------------------------------
# Intrinsic check.

function intrinsic_check(::D.Web, A::SparseMatrix{Bool})
    n, m = size(A)
    n == m && return A
    checkerr(A, "The adjacency matrix of size $((m, n)) is not squared.")
end

#-------------------------------------------------------------------------------------------
# Late check.

function late_check(m::Model, d::D.Web, A::SparseMatrix{Bool})
    a, b = size(A)
    src, _ = D.source(d)
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
    A
end

function late_check(m::Model, d::D.Web, adj::BinAdjacency{Symbol})
    class = D.sourcename(d)
    index = getproperty(m, class)._index
    check_refs(d, adj) do side, lab
        N.is_label(index, lab) ||
            checkerr(lab, "Not a $side label among $(repr(class)).")
    end
end

function late_check(m::Model, d::D.Web, adj::BinAdjacency{Int})
    class = D.sourcename(d)
    index = getproperty(m, class)._index
    n = length(index)
    check_refs(d, adj) do side, i
        N.is_index(index, i) ||
            checkerr(i, "Not a valid $side $(repr(class)) index among $n nodes.")
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

function expand!(m::Model, d::D.Web, A::AbstractSparseMatrix)
    topology = N.SparseReflexive(A)
    expand!(m, d, topology)
end

function expand!(m::Model, d::D.Web, adj::BinAdjacency)
    class = D.sourcename(d)
    index = getproperty(m, class)._index
    to_i(label) = N.to_index(index, label)
    topology = N.SparseReflexive(length(index), I.map(adj) do (src, sub)
        (to_i(src), I.map(to_i, sub))
    end)
    expand!(m, d, topology)
end

function expand!(m::Model, d::D.Web, top::Topology)
    c = D.sourcename(d)
    w = D.web(d)
    network = N.network(m)
    N.add_web!(network, w, (c, c), top)
    post_expand!(m, d)
end

# Extension point.
post_expand!(::Model, ::D.Web) = nothing

# ==========================================================================================
# Display.

function F.display_blueprint_field_long(
    io::IO,
    adj::BinAdjacency,
    ::ReflexiveWebAdjacencyBlueprint,
)
    println(io, "$black{$reset")
    bc = "$black,$reset"
    srcs = I.map(adj) do (src, sub)
        subs = join_elided(sub, "$bc "; repr = false)
        "    $src $black-> {$reset $subs $black}$reset"
    end
    print(io, join_elided(srcs, "$bc\n"; repr = false))
    print(io, "$bc\n  $black}$reset")
end
