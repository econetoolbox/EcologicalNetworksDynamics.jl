# Test failures in graph views.

import EcologicalNetworksDynamics.Views
import EcologicalNetworksDynamics.Networks

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

function TestFailures.check_exception(e::Networks.LabelError, e_name, e_class)
    (; name, class) = e
    e_name == name ||
        error("Expected wrong label name: $(repr(e_name)), got instead: $(repr(name))")
    e_name == name ||
        error("Expected class name: $(repr(e_class)), got instead: $(repr(class))")
end

macro labelfails(xp, name, class)
    TestFailures.failswith(
        __source__,
        __module__,
        xp,
        :($(Networks.LabelError) => $(name, class)),
        false,
    )
end
export @labelfails
