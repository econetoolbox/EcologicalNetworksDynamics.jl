# Test failures in graph views.

import EcologicalNetworksDynamics.Views

function TestFailures.check_exception(e::Views.Error, type, message_pattern)
    e.type == type ||
        error("Expected error for view type '$type', got '$(e.type)' instead.")
    TestFailures.check_message(message_pattern, eval(e.message))
end

macro viewfails(xp, type, mess)
    TestFailures.failswith(
        __source__,
        __module__,
        xp,
        :($(Views.Error) => ($type, $mess)),
        false,
    )
end
export @viewfails
