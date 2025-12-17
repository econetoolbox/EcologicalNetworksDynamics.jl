module Doctest

using Documenter
import EcologicalNetworksDynamics

DocMeta.setdocmeta!(
    EcologicalNetworksDynamics,
    :DocTestSetup,
    :(using EcologicalNetworksDynamics);
    recursive = true,
)

doctest(
    EcologicalNetworksDynamics;
    manual = false, # XXX: restore once all refactoring is over.
)

end
