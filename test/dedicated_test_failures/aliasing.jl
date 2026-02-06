# Check failures in aliasing systems.

import EcologicalNetworksDynamics.AliasingDicts: AliasingError

function TestFailures.check_exception(e::AliasingError, name, message_pattern)
    e.name == name ||
        error("Expected error for '$name' aliasing system, got '$(e.name)' instead.")
    TestFailures.check_message(message_pattern, eval(e.message))
end

macro xaliasfails(xp, name, mess)
    TestFailures.failswith(
        __source__,
        __module__,
        xp,
        :($(AliasingError) => ($name, $mess)),
        true,
    )
end
export @xaliasfails

macro aliasfails(xp, name, mess)
    TestFailures.failswith(
        __source__,
        __module__,
        xp,
        :($(AliasingError) => ($name, $mess)),
        false,
    )
end
export @aliasfails
