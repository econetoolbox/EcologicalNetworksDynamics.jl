# Check failures in aliasing systems.

import EcologicalNetworksDynamics.AliasingDicts: AliasError

function TestFailures.check_exception(e::AliasError, name, message_pattern)
    e.name == name ||
        error("Expected error for '$name' aliasing system, got '$(e.name)' instead.")
    TestFailures.check_message(message_pattern, eval(e.message))
end

macro aliasfails(xp, name, mess)
    TestFailures.failswith(
        __source__,
        __module__,
        xp,
        :($(AliasError) => ($name, $mess)),
        false,
    )
end
export @aliasfails
