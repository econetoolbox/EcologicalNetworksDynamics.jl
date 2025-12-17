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
    Class_ = Symbol(Class, :Blueprints) # Blueprints module name.
    _Class = Symbol(:_, Class) # Component type name.
    sclass, sp = Meta.quot.((class, short_prefix))
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

    end
    mod.eval.(xp.args)
end
