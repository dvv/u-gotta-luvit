require('zmq')

local context = zmq_init(1)

-- listening to messages
print('Push to *:65454')
local sub = context:socket(zmq.SUB)
sub:bind('tcp://localhost:65454')
sub:sockopt(ZMQ_SUBSCRIBE, '')

-- publishing to subscribers
print('Subscribe to *:65455\n')
pub = context:socket(zmq.PUB)
pub:bind('tcp://*:65455')

-- loop
while true do
  local msg = sub:recv()
  pub:send(msg)
end
