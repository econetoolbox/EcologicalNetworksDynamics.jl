"Expand into a new edges web."
abstract type WebBlueprint <: Blueprint end

"Expand into a new reflexive web from a sparse boolean matrix."
abstract type ReflexiveWebMatrixBlueprint <: WebBlueprint end

"Expand into a new reflexive web from an adjacency list."
abstract type ReflexiveWebAdjacencyBlueprint <: WebBlueprint end

"Typical setup for a component bringing a new reflexive web to the network."
function define_reflexive_web_component(mod::Module, s::SL.Web)
    S = typeof(s)
    prop, Prop = SL.propnames(s)
    src = SL.source(s)
    Class = SL.component(src)

    web, Web = SL.name_variants(s)
    class, same = SL.sidenames(s)
    same == class || argerr("Reflexive webs must match source and target, \
                             here $(repr(class)) != $(repr(same)).")
    w = Meta.quot(web) # Symbol names.

    # ======================================================================================
    # Blueprints for the component.

    # Prepare dedicated blueprints module and populate namespace.
    Blueprints = Symbol(Web, :Blueprints)
    bpmod = mod.eval(
        (
            quote
                module $Blueprints
                using EcologicalNetworksDynamics.Interface:
                    IT, SparseMatrix, BinAdjacency, Model, @bp_construct
                const s, src, Class = $s, $src, $Class
                end
            end
        ).args |> last,
    )

    #---------------------------------------------------------------------------------------
    # From matrix.
    bpmod.eval(
        quote
            mutable struct Matrix <: IT.ReflexiveWebMatrixBlueprint
                A::SparseMatrix{Bool}
                @bp_construct Matrix
            end
            export Matrix
            IT.register_blueprint(Matrix, "boolean matrix of $($w) links"; s,
                implied = [Class], # Infer number of class nodes from matrix size.
            )
        end,
    )

    #---------------------------------------------------------------------------------------
    # From ajacency list.
    bpmod.eval(
        quote
            mutable struct Adjacency <: IT.ReflexiveWebAdjacencyBlueprint
                A::BinAdjacency
                @bp_construct Adjacency
            end
            export Adjacency
            IT.register_blueprint(Adjacency, "adjacency list of $($w) links"; s,
                implied = [Class], # Infer number or names of class nodes from the lists.
            )
        end,
    )

    # ======================================================================================
    # Component and generic constructors.

    CPname = s |> SL.componentname |> Meta.quot
    cp = IT.eval(
        quote
            define_component($CPname, $mod; requires = ($Class,), blueprints = ($bpmod,))
        end,
    )
    CP = typeof(cp)
    IT.eval(quote
        $SL.component(::$S) = $cp
        (::$CP)(args...; kwargs...) = IT.construct($s, $cp, args...; kwargs...)
    end)

    define_web_properties(mod, s; depends = [CP])

    (cp, CP)
end

# ==========================================================================================

function define_web_properties(mod::Module, s::SL.Web; depends = [])
    w = SL.webname(s)
    web, Web = SL.name_variants(s)
    prop, Prop = SL.propnames(s)

    IT.define_propspace(prop)
    IT.define_propspace(:($prop.iter))
    IT.define_propspace(:($prop.iter.index))
    IT.define_propspace(:($prop.iter.label))
    defmeth(fn, props) =
        IT.define_method(fn; depends, read_as = map(p -> paste_paths(prop, p), props))

    Methods = Symbol(Web, :Methods)
    mod.eval(
        (
            quote
                module $Methods
                using EcologicalNetworksDynamics.Interface:
                    I, ST, VW, SL, Network, Model
                const s, defmeth, w = $s, $defmeth, $(Meta.quot(w))

                web(nw::Network) = ST.web(nw, w)
                topology(nw::Network) = web(nw).topology
                number(nw::Network) = nw |> topology |> ST.n_edges
                mask(::Network, md::Model) = VW.mask_view(s, md)

                defmeth(topology, [:_topology])
                defmeth(mask, [:mask, :matrix])
                defmeth(number, [:n_links, :n_edges])

                #---------------------------------------------------------------------------
                # Edges iterators.

                edges(nw::Network) = nw |> topology |> ST.edges
                forward(nw::Network) = nw |> topology |> ST.forward
                backward(nw::Network) = nw |> topology |> ST.backward

                # Variants: reverse or skip empty subgroups.
                edges_transposed(nw::Network) = nw |> topology |> ST.edges_transposed
                forward_skip(nw::Network) = ST.forward(topology(nw), skip = true)
                backward_skip(nw::Network) = ST.backward(topology(nw), skip = true)

                # Produce labeled variants.
                function labeled_flat(fn::Function)
                    function labeled(nw::Network)
                        index = ST.source(nw, w).index
                        I.map(fn(nw)) do (i, j)
                            ST.to_label.((index,), (i, j))
                        end
                    end
                end
                function labeled_nested(fn::Function)
                    function labeled(nw::Network)
                        index = ST.source(nw, w).index
                        I.map(fn(nw)) do (i, sub)
                            (ST.to_label(index, i), I.map(sub) do (j, e)
                                (ST.to_label(index, j), e)
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

#-------------------------------------------------------------------------------------------
# Construct.

# Pick blueprint depending on input conversion success.
function construct(s::SL.Web, Web::Component, input, args...; kwargs...)
    try
        try_convert(
            input,
            SparseMatrix{Bool} => A -> Web.Matrix(A, args...; kwargs...),
            BinAdjacency => A -> Web.Adjacency(A, args...; kwargs...),
        )
    catch e
        e isa LibError || rethrow(e)
        if e isa ConvertError
            e = CheckError(e)
        end
        if e isa CheckError
            e.s = s
        end
        rethrow(e)
    end
end

#-------------------------------------------------------------------------------------------
# Implied class blueprint.

function implied(::SL.Web, Class::Component, bp::ReflexiveWebMatrixBlueprint)
    (; A) = bp
    n = size(A, 1)
    Class.Number(n)
end

implied(s::SL.Web, Class::Component, bp::ReflexiveWebAdjacencyBlueprint) =
    implied(s, Class, bp.A) # Dispatch over ref type: indices or labels.

function implied(::SL.Web, Class::Component, adj::BinAdjacency{Symbol})
    refs = IT.all_refs(adj)
    Class.Names(collect(refs))
end

function implied(::SL.Web, Class::Component, adj::BinAdjacency{Int})
    refs = IT.all_refs(adj)
    Class.Number(last(refs))
end

#-------------------------------------------------------------------------------------------
# Early check.

function early_check(::SL.Web, A::SparseMatrix{Bool})
    m, n = size(A)
    m == n && return A
    checkerr(A, "The adjacency matrix of size $((m, n)) is not squared.")
end

#-------------------------------------------------------------------------------------------
# Late check.

function late_check(md::Model, s::SL.Web, A::SparseMatrix{Bool})
    a, b = size(A)
    src = SL.source(s)
    class = SL.snake_case_singular(src)
    n = getproperty(md, class).number
    if !(n == a == b)
        src = SL.sourcename(s)
        (are, s) = n == 1 ? ("is", "") : ("are", "s")
        checkerr(
            A,
            "There $are $n $(repr(src)) node$s \
             but the provided matrix is of size ($a, $b).",
        )
    end
    A
end

function late_check(md::Model, s::SL.Web, adj::BinAdjacency{Symbol})
    class = SL.sourcename(s)
    index = getproperty(md, class)._index
    check_refs(s, adj) do side, lab
        ST.is_label(index, lab) ||
            checkerr(lab, "Not a $side label among $(repr(class)).")
    end
end

function late_check(md::Model, s::SL.Web, adj::BinAdjacency{Int})
    class = SL.sourcename(s)
    index = getproperty(md, class)._index
    n = length(index)
    check_refs(s, adj) do side, i
        ST.is_index(index, i) ||
            checkerr(i, "Not a valid $side $(repr(class)) index among $n nodes.")
    end
end

function check_refs(check::Function, ::SL.Web, adj::BinAdjacency)
    path = Path()
    try
        for (i, (src, sub)) in enumerate(adj)
            push!(path, i)
            push!(path, :left)
            check("source", src)
            pop!(path)
            push!(path, :right)
            for (j, tgt) in enumerate(sub)
                push!(path, j)
                check("target", tgt)
                pop!(path)
            end
            pop!(path)
            pop!(path)
        end
    catch e
        e isa CheckError || rethrow(e)
        e.ref = UserRef(path)
        rethrow(e)
    end
    adj
end

#-------------------------------------------------------------------------------------------
# Expand.

function expand!(md::Model, s::SL.Web, A::AbstractSparseMatrix)
    topology = ST.SparseReflexive(A)
    expand!(md, s, topology)
end

function expand!(md::Model, s::SL.Web, adj::BinAdjacency)
    c = SL.sourcename(s)
    ix = getproperty(md, c)._index
    n = length(ix)
    to_i(l) = ST.to_index(ix, l)
    topology = ST.SparseReflexive(n, I.map(adj) do (src, sub)
        (to_i(src), I.map(to_i, sub))
    end)
    expand!(md, s, topology)
end

function expand!(md::Model, s::SL.Web, top::Topology)
    c = SL.sourcename(s)
    w = SL.webname(s)
    network = ST.network(md)
    ST.add_web!(network, w, (c, c), top)
    post_expand!(md, s)
end

# Extension point.
post_expand!(::Model, ::SL.Web) = nothing

#-------------------------------------------------------------------------------------------
# Obtain.

function obtain(md::Model, s::SL.Web, (i, j)::Tuple{Int,Int})
    top = ST.web(md, s).topology
    ST.is_edge(top, i, j)
end

# Accept mixtures of ranges and scalars.
function obtain(md::Model, s::SL.Web, (i, rj)::Tuple{Ref,UnitRange})
    res = spzeros(Bool, length(rj))
    for j in rj
        k = j - first(rj) + 1
        res[k] = obtain(md, s, (i, j))
    end
    res
end

function obtain(md::Model, s::SL.Web, (ri, j)::Tuple{UnitRange,Ref})
    res = spzeros(Bool, length(ri))
    for i in ri
        k = i - first(ri) + 1
        res[k] = obtain(md, s, (i, j))
    end
    res
end

function obtain(md::Model, s::SL.Web, (ri, rj)::Tuple{UnitRange,UnitRange})
    res = spzeros(Bool, (length(ri), length(rj)))
    for i in ri, j in rj
        ki = i - first(ri) + 1
        kj = j - first(rj) + 1
        res[ki, kj] = obtain(md, s, (i, j))
    end
    res
end

# 2D indexing into edges mask.
function obtain(md::Model, s::SL.Web, (mat,)::Tuple{SparseMatrix{Bool}})
    is, js, _ = findnz(mat)
    res = spzeros(Bool, length(is))
    for (r, (i, j)) in enumerate(zip(is, js))
        res[r] = obtain(md, s, (i, j))
    end
    res
end

# ==========================================================================================
# Display.

function CS.display_blueprint_field_long(
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
