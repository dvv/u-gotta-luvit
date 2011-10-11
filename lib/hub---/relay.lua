-- these are required by ZMQ
bit = require('bit')
debug = require('debug')
local ZMQ = require('zmq')

-- context
local ctx = ZMQ.init(1)

-- listening to messages
local sub = ctx:socket(ZMQ.SUB)
sub:bind('tcp://*:65454')
sub:setopt(ZMQ.SUBSCRIBE, '')
print('Push to *:65454')

-- publishing to subscribers
local pub = ctx:socket(ZMQ.PUB)
pub:bind('tcp://*:65455')
print('Subscribe to *:65455\n')

-- loop
while true do
  -- on received message...
  local msg = sub:recv()
  -- ...relay it to subscribers
  pub:send(msg)
end
