"""
Typical setup for a component bringing a new reflexive web to the network.
"""
function define_reflexive_web_component(mod::Module, ew::EdgeWeb)

    prop, Prop = propnames(ew)
    web, Web = name_variants(ew)
    class, same = sidenames(ew)
    same == class || argerr("Reflexive webs must match source and target, \
                             here $(repr(class)) != $(repr(same)).")
    nc = source(ew)
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
                        GraphDataInputs,
                        @blueprint,
                        NetworkConfig
                    using .GraphDataInputs
                    using .Framework
                    using .Networks
                    const F = Framework
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
                    new(graphdataconvert(SparseMatrix{Bool}, A), $class)
            end
            # Infer number of class nodes from matrix size.
            F.implied_blueprint_for(bp::Matrix, ::_Class) = Class(size(bp.A, 1))
            F.early_check(bp::Matrix) = $reflexive_web_matrix_early_check(bp.A)
            F.late_check(_, bp::Matrix, model) =
                $reflexive_web_matrix_late_check(ew, bp.A, model)
            F.expand!(raw, bp::Matrix, _, model) =
                $reflexive_web_expand_from_matrix!(ew, raw, bp.A, model)
            @blueprint Matrix "boolean matrix of $($w) links"
            export Matrix
        end,
    )

    # From ajacency list.
    blueprints.eval(
        quote
            mutable struct Adjacency <: Blueprint
                A::@GraphData {Adjacency}{:bin} # (refs are either numbers or names)
                $class::Brought(Class)
                Adjacency(A, $class = Class) =
                    new(@tographdata(A, {Adjacency}{:bin}), $class)
            end
            # Infer number or names of class nodes from the lists.
            F.implied_blueprint_for(bp::Adjacency, ::_Class) = Class(refspace(bp.A))
            F.late_check(raw, bp::Adjacency, model) =
                $reflexive_web_adjacency_late_check(ew, raw, bp.A, model)
            F.expand!(raw, bp::Adjacency, _, model) =
                $reflexive_web_adjacency_expand!(ew, raw, bp.A, model)
            @blueprint Adjacency "adjacency list of $($w) links"
            export Adjacency
        end,
    )

    # ======================================================================================
    # Component and generic constructors.

    EW = typeof(ew)
    Class = CamelCasePlural(nc)
    mod.eval(quote
        @component $Web{Internal} requires($Class) blueprints($Web_)
        C.component(::$EW) = $Web
        (::$_Web)(A) = $reflexive_web_construct($Web, A)
    end)

    define_web_properties(mod, ew, :(depends($Web)))
end

# ==========================================================================================

function define_web_properties(
    mod::Module,
    ew::EdgeWeb,
    deps::Expr, # As in a regular call to @method.
)
    web, Web = name_variants(ew)
    prop, Prop = propnames(ew)
    w = Meta.quot(web)
    M = Symbol(Web, :Methods) # Create submodule to not pollute invocation scope..
    m = :(mod($mod)) # .. but still evaluate dependencies within the invocation module.
    xp = quote

        @propspace $prop

        module $M
        import EcologicalNetworksDynamics: Internal, Model, Networks, Framework, Views
        using .Networks
        using .Framework
        using .Views

        web(m::Internal) = Networks.web(m, $w)
        topology(m::Internal) = web(m).topology
        number(m::Internal) = m |> topology |> n_edges
        mask(::Internal, m::Model) = edges_mask_view(m, $w)
        @method $m $M.topology $deps read_as($prop._topology)
        @method $m $M.mask $deps read_as($prop.matrix, $prop.mask)
        @method $m $M.number $deps read_as($prop.n_links, $prop.n_edges)

        end
    end

    mod.eval.(xp.args)
end

# ==========================================================================================
# Extract implementation detail to ease Revise work.

function reflexive_web_expand_from_matrix!(ew::EdgeWeb, raw, A, model)
    topology = N.SparseReflexive(A)
    c = sourcename(ew)
    w = web(ew)
    N.add_web!(raw, w, (c, c), topology)
    # Possible extension point.
    reflexive_web_post_expand!(ew, raw, topology, A, model)
end
reflexive_web_post_expand!(::EdgeWeb, network, topology, matrix, model) = nothing

# Check shape.
function reflexive_web_matrix_early_check(A::AbstractMatrix)
    n, m = size(A)
    n == m || F.checkfails("The adjacency matrix of size $((m, n)) is not squared.")
end

function reflexive_web_matrix_late_check(ew::EdgeWeb, A, model)
    a, b = size(A)
    class = snake_case_singular(source(ew))
    n = getproperty(model, class).number
    if !(n == a == b)
        src = sourcename(ew)
        (are, s) = n == 1 ? ("is", "") : ("are", "s")
        F.checkfails("There $are $n $(repr(src)) node$s \
                    but the provided matrix is of size ($a, $b).")
    end
end

function reflexive_web_adjacency_late_check(ew::EdgeWeb, network, A, model)
    p, _ = propnames(ew)
    class = sourcename(ew)
    index = getproperty(model, class)._index
    # HERE: this needs simpler rewrite.
    GraphDataInputs.check_list_refs(A, index, nothing, :A, "$p link")
    A
end

function reflexive_web_adjacency_expand!(ew::EdgeWeb, raw, A, model)
    class = sourcename(ew)
    index = getproperty(model, class)._index
    A = to_sparse_matrix(A, index, index) # HERE: this goes to Inputs/expand.jl
    reflexive_web_expand_from_matrix!(ew, raw, A, model)
end

# Precise edges specifications.
function reflexive_web_construct(Web::Component, A)
    # HERE: resurrect these chained conversions, or just try-catch here?
    A = @tographdata A {SparseMatrix, Adjacency}{:bin}
    if A isa AbstractMatrix
        Web.Matrix(A)
    else
        Web.Adjacency(A)
    end
end
