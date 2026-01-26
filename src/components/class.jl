"""
Typical setup for a component bringing a new class to the network.
"""
macro class_component(input...)
    quote
        $define_class_component($__module__, $(Meta.quot.(input)...))
        nothing
    end
end

function define_class_component(
    mod::Module,
    # Class name, singular/plural, capitalized/not.
    singular::Symbol,
    Singular::Symbol,
    plural::Symbol,
    Plural::Symbol,
    # Prefix for automatically generated node labels.
    short_prefix::Symbol,
)
    Plural_ = Symbol(Plural, :_) # Blueprints module name.
    _Plural = Symbol(:_, Plural) # Component type name.
    s, S, sp = Meta.quot.((plural, Plural, short_prefix)) # Symbol names.
    xp = quote

        # ==================================================================================
        # Blueprints for the component.
        module $Plural_
        import EcologicalNetworksDynamics:
            Blueprint, Framework, Networks, GraphDataInputs, @blueprint
        const F = Framework
        const G = GraphDataInputs

        #-------------------------------------------------------------------------------
        # Construct from a given set of names.
        mutable struct Names <: Blueprint
            names::Vector{Symbol}
            # Convert anything to symbols.
            Names(names) = new(G.@tographdata names Vector{Symbol})
            Names(names...) = new(Symbol.(collect(names)))

            # From an index (useful when implied).
            function Names(index::AbstractDict{Symbol,Int})
                G.check_index(index)
                new(G.to_dense_refs(index))
            end

            # Don't own data if useful to user.
            Names(names::Vector{Symbol}) = new(names)
        end

        @blueprint Names "raw $($s) names"
        export Names

        # Forbid duplicates (triangular check).
        function F.early_check(bp::Names)
            (; names) = bp
            for (i, a) in enumerate(names)
                for j in (i+1):length(names)
                    b = names[j]
                    a == b && G.checkfails("$($S) $i and $j are both named $(repr(a)).")
                end
            end
        end

        # Expand into a new compartment.
        F.expand!(raw, bp::Names) = expand!(raw, bp.names)
        expand!(raw, names) = Networks.add_class!(raw, $s, names)

        #-----------------------------------------------------------------------------------
        # Construct from a plain number and generate dummy names.

        mutable struct Number <: Blueprint
            n::UInt
        end
        @blueprint Number "number of $($s)"
        export Number

        F.expand!(raw, bp::Number) = expand!(raw, [Symbol($sp, i) for i in 1:bp.n])

        end

        # ==================================================================================
        # The component itself and generic blueprints constructors.

        @component $Plural{Internal} blueprints($Plural_)

        # Build from a number or default to names.
        (::$_Plural)(n::Integer) = $Plural.Number(n)
        (::$_Plural)(names) = $Plural.Names(names)

        # ==================================================================================
        # Display.

        function Framework.shortline(io::IO, model::Model, ::$_Plural)
            names = model.$plural._names
            n = length(names)
            print(io, "$($S): $n ($(join_elided(names, ", ")))")
        end

    end
    mod.eval.(xp.args)
    define_class_properties(mod, plural, Plural, singular, Singular, :(depends($Plural)))
end

# ==========================================================================================

"""
Some classes are not directly defined by a component,
e.g. 'producers' is defined by the foodweb,
but the need the same exposure: use it to expose them.
"""
macro class_properties(input...)
    quote
        $define_class_properties($__module__, $(Meta.quot.(input)...))
        nothing
    end
end

function define_class_properties(
    mod::Module,
    singular::Symbol,
    Singular::Symbol,
    plural::Symbol,
    Plural::Symbol,
    deps::Expr, # As in a regular call to @method.
)
    s = Meta.quot(plural)
    M = Symbol(Plural, :Methods) # Create submodule to not pollute invocation scope..
    m = :(mod($mod)) # .. but still evaluate dependencies within the invocation module.
    xp = quote

        @propspace $plural

        module $M
        import EcologicalNetworksDynamics: Internal, Model, Networks, Framework, Views
        using .Networks
        using .Framework
        using .Views

        # Nodes counts and nodes labels.
        # The 'ref' variant is more efficient but unexposed.
        get_number(m::Internal) = n_nodes(m, $s)
        ref_names(m::Internal) = class(m, $s).index.reverse
        get_names(::Internal, m::Model) = nodes_names_view(m, $s)
        @method $m $M.get_number $deps read_as($plural.number)
        @method $m $M.ref_names $deps read_as($plural._names)
        @method $m $M.get_names $deps read_as($plural.names)

        # Ordered index.
        ref_index(m::Internal) = class(m, $s).index.forward
        get_index(m::Internal) = deepcopy(ref_index(m))
        indices(m::Internal) = Networks.node_indices(m, $s)
        @method $m $M.ref_index $deps read_as($plural._index)
        @method $m $M.get_index $deps read_as($plural.index)
        @method $m $M.indices $deps read_as($plural.indices)

        # Mask within parent class.
        mask(i::Internal, m::Model) = nodes_mask_view(m, ($s, class(i, $s).parent))
        @method $m $M.mask $deps read_as($plural.mask)

        end
    end

    mod.eval.(xp.args)
end
