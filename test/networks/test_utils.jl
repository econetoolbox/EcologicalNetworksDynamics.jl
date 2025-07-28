module TestNetworksUtils

using EcologicalNetworksDynamics.Networks
import Main.TestFailures as T

function T.check_exception(e::Networks.NetworkError, message_pattern)
    T.check_message(message_pattern, eval(e.mess))
end
macro netfails(xp, mess)
    T.failswith(__source__, __module__, xp, :(Networks.NetworkError => ($mess,)), false)
end
export @netfails

end
