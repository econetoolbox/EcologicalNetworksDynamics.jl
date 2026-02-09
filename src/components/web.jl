"""
Typical setup for a component bringing a new reflexive web to the network.
"""
macro reflexive_web_component(input...)
    quote
        $define_reflexive_web_component($__module__, $(Meta.quot.(input)...))
        nothing
    end
end

# If extension points are used, this form is more ergonomic.
function define_reflexive_web_component(
    mod::Module,
    # Web name (capitalized and not).
    web::Symbol,
    Web::Symbol,
    # Dependent/Brought class that the web is reflexive within.
    class::Symbol,
    Class::Union{Symbol,Expr}; # Path to the actual class component.
    # Property name, if different from web name.
    prop = (web, Web),
    # Extension points.
    expand_from_matrix! = (raw, topology, A, model) -> nothing,
)
    prop, Prop = prop
    Web_ = Symbol(Web, :_) # Blueprints module name.
    _Web = Symbol(:_, Web) # Component type name.
    w, c, p = Meta.quot.((web, class, prop)) # Symbol names.
    xp = quote

        # ==================================================================================
        # Blueprints for the component.
        module $Web_
        import EcologicalNetworksDynamics:
            Blueprint, Framework, Networks, GraphDataInputs, @blueprint
        using .GraphDataInputs
        using .Framework
        using .Networks
        const F = Framework
        const Class = $mod.$Class
        const _Class = typeof(Class)

        #-----------------------------------------------------------------------------------
        # From matrix.

        mutable struct Matrix <: Blueprint
            A::@GraphData SparseMatrix{:bin}
            $class::Brought(Class)
            Matrix(A, $class = Class) = new(@tographdata(A, SparseMatrix{:bin}), $class)
        end

        # Infer number of class nodes from matrix size.
        F.implied_blueprint_for(bp::Matrix, ::_Class) = Class(size(bp.A, 1))
        @blueprint Matrix "boolean matrix of $($w) links"
        export Matrix

        function F.early_check(bp::Matrix)
            (; A) = bp
            n, m = size(A)
            n == m ||
                checkfails("The adjacency matrix of size $((m, n)) is not squared.")
        end

        function F.late_check(_, bp::Matrix, model)
            (; A) = bp
            n = model.$class.number
            @check_size A (n, n)
        end

        F.expand!(raw, bp::Matrix, model) = expand_from_matrix!(raw, bp.A, model)
        function expand_from_matrix!(raw, A, model)
            topology = SparseReflexive(A)
            add_web!(raw, $p, ($c, $c), topology)
            $expand_from_matrix!(raw, topology, A, model)
        end

        #-----------------------------------------------------------------------------------
        # From ajacency list.

        mutable struct Adjacency <: Blueprint
            A::@GraphData {Adjacency}{:bin} # (refs are either numbers or names)
            $class::Brought(Class)
            Adjacency(A, $class = Class) =
                new(@tographdata(A, {Adjacency}{:bin}), $class)
        end

        # Infer number or names of class nodes from the lists.
        F.implied_blueprint_for(bp::Adjacency, ::_Class) = Class(refspace(bp.A))

        @blueprint Adjacency "adjacency list of $($w) links"
        export Adjacency

        function F.late_check(_, bp::Adjacency, model)
            (; A) = bp
            index = model.$class._index
            @check_list_refs A $c index
        end

        function F.expand!(raw, bp::Adjacency, model)
            index = model.$class.index
            A = to_sparse_matrix(bp.A, index, index)
            expand_from_matrix!(raw, A, model)
        end

        end

        # ==================================================================================
        # Component and generic constructors.

        @component $Web{Internal} requires($Class) blueprints($Web_)

        # Precise edges specifications.
        function (::$_Web)(A)
            A = @tographdata A {SparseMatrix, Adjacency}{:bin}
            if A isa AbstractMatrix
                $Web.Matrix(A)
            else
                $Web.Adjacency(A)
            end
        end

    end
    mod.eval.(xp.args)
    define_web_properties(mod, prop, Prop, :(depends($Web)))
end


# ==========================================================================================

"""
Some webs are not directly defined by a component,
e.g. 'producers links' is defined by the foodweb,
but the need the same exposure: use it to expose them.
"""
macro web_properties(input...)
    quote
        $define_web_properties($__module__, $(Meta.quot.(input)...))
        nothing
    end
end

function define_web_properties(
    mod::Module,
    web::Symbol,
    Web::Symbol,
    deps::Expr, # As in a regular call to @method.
)
    w = Meta.quot(web)
    M = Symbol(Web, :Methods) # Create submodule to not pollute invocation scope..
    m = :(mod($mod)) # .. but still evaluate dependencies within the invocation module.
    xp = quote

        @propspace $web

        module $M
        import EcologicalNetworksDynamics: Internal, Model, Networks, Framework, Views
        using .Networks
        using .Framework
        using .Views

        web(m::Internal) = Networks.web(m, $w)
        topology(m::Internal) = web(m).topology
        number(m::Internal) = m |> topology |> n_edges
        mask(::Internal, m::Model) = edges_mask_view(m, $w)
        @method $m $M.topology $deps read_as($web._topology)
        @method $m $M.mask $deps read_as($web.matrix, $web.mask)
        @method $m $M.number $deps read_as($web.n_links, $web.n_edges)

        end
    end

    mod.eval.(xp.args)
end
