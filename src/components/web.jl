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
    s = Meta.quot(web)
    M = Symbol(Web, :Methods) # Create submodule to not pollute invocation scope..
    m = :(mod($mod)) # .. but still evaluate dependencies within the invocation module.
    xp = quote

        @propspace $web

        module $M
        import EcologicalNetworksDynamics: Internal, Model, Networks, Framework, Views
        using .Networks
        using .Framework
        using .Views

        web(m::Internal) = Networks.web(m, $s)
        topology(m::Internal) = web(m).topology
        number(m::Internal) = m |> topology |> n_edges
        mask(::Internal, m::Model) = edges_mask_view(m, $s)
        @method $m $M.topology $deps read_as($web._topology)
        @method $m $M.mask $deps read_as($web.matrix, $web.mask)
        @method $m $M.number $deps read_as($web.n_links, $web.n_edges)

        end
    end

    mod.eval.(xp.args)
end
