"""
Expand into a graph-level scalar given the value.
"""
abstract type GraphScalarBlueprint <: Blueprint end

"""
Typical setup for a component bringing a new graph-level scalar data to the network.
The data is passed as-is to the internals, so it is enforced to be immutable.
"""
function define_graph_scalar(mod::Module, d::D.GraphField)
    shortname, singular, Singular = D.name_variants(d)
    Singular_ = Symbol(Singular, :_)

    T = D.type(d)
    N.is_deep_immutable(T) || throw(
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
                import EcologicalNetworksDynamics: F, NF
                const d = $d
                const T = $T

                mutable struct Raw <: NF.GraphScalarBlueprint
                    $field::T
                    Raw(input) = new(NF.check(d, NF.inputconvert(T, input)))
                end
                NF.data(bp::Raw) = bp.$field
                F.early_check(bp::Raw) = NF.early_check(d, bp)
                F.expand!(model, bp::Raw) = NF.expand!(d, model, bp)
                F.define_blueprint(Raw, "raw $($(Meta.quot(singular))) value")
                export Raw

                end
            end
        ).args |> last,
    )

    # ======================================================================================
    # The component itself.

    comp = mod.eval(
        quote
            $NF.define_component($(Meta.quot(Singular)), $mod; blueprints = [$bpmod])
        end,
    )
    C = typeof(comp)
    DT = typeof(d)
    mod.eval(
        quote
            D.component(::$DT) = $comp
            (::$C)(input) = $comp.Raw(input)
            $F.shortline(io::IO, model::Model, ::$C) =
                $graph_scalar_shortline($d, io, model)
        end,
    )

    # ======================================================================================
    # Queries.

    M = Symbol(Singular, :Methods)
    props = [D.field(d), shortname]
    mod.eval(
        (
            quote
                module $M
                using EcologicalNetworksDynamics: V, NF, D, Network, Model
                const d = $d
                const props = $props
                const C = $C
                get_value(n::Network) = NF.get_value(d, n)
                NF.define_method(get_value; read_as = props, depends = [C])
                if !D.readonly(d)
                    set_value!(n::Network, input) = NF.reassign!(d, n, input)
                    NF.define_method(set_value!; write_as = props, depends = [C])
                end
                end
            end
        ).args |> last,
    )

    comp

end

early_check(d::D.GraphField, bp::GraphScalarBlueprint) =
    try
        check(d, data(bp))
    catch e
        e isa F.InputError || rethrow(e)
        with_context!(e, "When checking raw value for $d")
    end

function expand!(d::D.GraphField, m::Model, bp::GraphScalarBlueprint)
    field = D.field(d)
    data = NF.data(bp)
    n = N.network(m)
    N.add_field!(n, field, data)
end

function get_value(d::D.GraphField, n::Network)
    field = D.field(d)
    entry = n.data[field]
    N.read(entry) do value
        value # Just leak the value: it has been checked for immutability.
    end
end

function reassign!(d::D.GraphField, n::Network, input)
    T = D.type(d)
    conv = NF.inputconvert(T, input)
    checked = check(d, conv)
    field = D.field(d)
    entry = n.data[field]
    N.reassign!(entry, checked) # Just feed it down: typechecked for immutability.
end

function graph_scalar_shortline(d::D.GraphField, io, m::Model)
    field = D.field(d)
    Field = D.CamelCaseSingular(d)
    net = N.network(m)
    entry = net.data[field]
    read(entry) do value
        print(io, "$Field: $(repr(value))")
    end
end
