"""
Typical setup for a component bringing a new class to the network.
Provide lowercase + camelcase names and a short prefix for default labels.
"""
macro class_component(input...)
    quote
        $define_class_component($__module__, $(Meta.quot.(input)...))
        nothing
    end
end

function define_class_component(
    mod::Module,
    class::Symbol,
    Class::Symbol,
    short_prefix::Symbol,
)
    Class_ = Symbol(Class, :_) # Blueprints module name.
    _Class = Symbol(:_, Class) # Component type name.
    sclass, sClass, sp = Meta.quot.((class, Class, short_prefix))
    xp = quote

        # ==================================================================================
        # Blueprints for the component.
        module $Class_
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

        @blueprint Names "raw $($sclass) names"
        export Names

        # Forbid duplicates (triangular check).
        function F.early_check(bp::Names)
            (; names) = bp
            for (i, a) in enumerate(names)
                for j in (i+1):length(names)
                    b = names[j]
                    a == b &&
                        G.checkfails("$($sClass) $i and $j are both named $(repr(a)).")
                end
            end
        end

        # Expand into a new compartment.
        F.expand!(raw, bp::Names) = expand!(raw, bp.names)
        expand!(raw, names) = Networks.add_class!(raw, $sclass, names)

        #-----------------------------------------------------------------------------------
        # Construct from a plain number and generate dummy names.

        mutable struct Number <: Blueprint
            n::UInt
        end
        @blueprint Number "number of $($sclass)"
        export Number

        F.expand!(raw, bp::Number) = expand!(raw, [Symbol($sp, i) for i in 1:bp.n])

        end

        # ==================================================================================
        # The component itself and generic blueprints constructors.

        @component $Class{Internal} blueprints($Class_)

        # Build from a number or default to names.
        (::$_Class)(n::Integer) = $Class.Number(n)
        (::$_Class)(names) = $Class.Names(names)

        # ==================================================================================
        # Display.

        function Framework.shortline(io::IO, model::Model, ::$_Class)
            names = model.$class._names
            n = length(names)
            print(io, "$($sClass): $n ($(join_elided(names, ", ")))")
        end

    end
    mod.eval.(xp.args)
    define_class_properties(mod, class, Class, :(depends($Class)))
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
    class::Symbol,
    Class::Symbol,
    deps::Expr, # As in a regular call to @method.
)
    sclass = Meta.quot(class)
    M = Symbol(Class, :Methods) # Create submodule to not pollute invocation scope..
    m = :(mod($mod)) # .. but still evaluate dependencies within the invocation module.
    xp = quote

        @propspace $class

        module $M
        import EcologicalNetworksDynamics: Internal, Model, Networks, Framework, Views
        using .Networks
        using .Framework
        using .Views

        # Nodes counts and nodes labels.
        # The 'ref' variant is more efficient but unexposed.
        get_number(m::Internal) = n_nodes(m, $sclass)
        ref_names(m::Internal) = class(m, $sclass).index.reverse
        get_names(::Internal, m::Model) = nodes_names_view(m, $sclass)
        @method $m $M.get_number $deps read_as($class.number)
        @method $m $M.ref_names $deps read_as($class._names)
        @method $m $M.get_names $deps read_as($class.names)

        # Ordered index.
        ref_index(m::Internal) = class(m, $sclass).index.forward
        get_index(m::Internal) = deepcopy(ref_index(m))
        @method $m $M.ref_index $deps read_as($class._index)
        @method $m $M.get_index $deps read_as($class.index)

        # Mask within parent class.
        mask(i::Internal, m::Model) =
            nodes_mask_view(m, ($sclass, class(i, $sclass).parent))
        @method $m $M.mask $deps read_as($class.mask)

        end
    end

    mod.eval.(xp.args)
end
