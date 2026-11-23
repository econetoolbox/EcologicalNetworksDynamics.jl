"Expand into a graph-level scalar given the value."
abstract type GraphScalarBlueprint <: Blueprint end

"""
Typical setup for a component bringing a new graph-level scalar data to the network.
The data is passed as-is to the internals, so it is enforced to be immutable.
Returns the defined component and its type.
"""
function define_graph_field(mod::Module, s::SL.GraphField)
    S = typeof(s)
    shortname, singular, Singular = SL.name_variants(s)
    Singular_ = Symbol(Singular, :_)

    T = SL.type(s)
    ST.is_deep_immutable(T) || throw(
        "Cannot pick this type for graph-level scalar data because it is mutable: $T.",
    )

    # ======================================================================================
    # Only one blueprint for now.

    # Prepare dedicated blueprints module and populate namespace.
    field = shortname
    bpmod = mod.eval(
        (
            quote
                module $Singular_
                import EcologicalNetworksDynamics.NetworkFramework: NF, @bp_construct
                const s, T = $s, $T

                mutable struct Raw <: NF.GraphScalarBlueprint
                    $field::T
                    @bp_construct Raw
                end
                export Raw
                NF.register_blueprint(Raw, "raw $($("$singular")) value"; s)

                end
            end
        ).args |> last,
    )

    # ======================================================================================
    # The component itself.

    cp = NF.eval(
        quote # Need to reach toplevel first to access generated values.
            define_component($(Meta.quot(Singular)), $mod; blueprints = ($bpmod,))
        end,
    )
    CP = typeof(cp)
    NF.eval(
        quote
            SL.component(::$S) = $cp
            (::$CP)(input) = $cp.Raw(input)
            CS.shortline(io::IO, md::Model, ::$CP) = graph_scalar_shortline($s, io, md)
        end,
    )

    # ======================================================================================
    # Queries.

    M = Symbol(Singular, :Methods)
    props = [SL.fieldname(s), shortname]
    mod.eval(
        (
            quote
                module $M
                using EcologicalNetworksDynamics.NetworkFramework:
                    NF, SL, Network, Model
                const s, CP, props = $s, $CP, $props
                get_value(::Network, md::Model) = NF.get_value(md, s)
                NF.define_method(get_value; read_as = props, depends = [CP])
                if !SL.readonly(s)
                    set_value!(::Network, md::Model, input) =
                        NF.mut_set!(md, s, NF.wholedata, input)
                    NF.define_method(set_value!; write_as = props, depends = [CP])
                end
                end
            end
        ).args |> last,
    )

    (cp, CP)

end

# ==========================================================================================
# Specialisation for this typical component type.
# The data may be aliased throughout the default lowering pipeline,
# because it has been checked for immutability anyway.

function expand!(md::Model, s::SL.GraphField, low)
    nw, f = ST.network(md), SL.fieldname(s)
    ST.add_field!(nw, f, low)
end

function get_value(md::Model, s::SL.GraphField)
    entry = ST.entry(md, s)
    ST.read(entry) do value
        value # Just leak it: immutable.
    end
end

function mutate!(md::Model, s::SL.GraphField, ::WholeData, low)
    entry = ST.entry(md, s)
    ST.reassign!(entry, low)
end

#-------------------------------------------------------------------------------------------
# Display.

function graph_scalar_shortline(s::SL.GraphField, io, md::Model)
    cc = CS.component_color
    fc = CS.field_color
    Field = SL.CamelCaseSingular(s)
    entry = ST.entry(md, s)
    read(entry) do value
        print(io, "$cc$Field$reset: $fc$(repr(value))$reset")
    end
end
