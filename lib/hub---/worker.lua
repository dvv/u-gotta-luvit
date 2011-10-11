-- these are required by ZMQ
bit = require('bit')
debug = require('debug')
local ZMQ = require('zmq')

-- context
local ctx = ZMQ.init(1)

-- listening to relayed
local sub = ctx:socket(ZMQ.SUB)
sub:connect('tcp://localhost:65455')
sub:setopt(ZMQ.SUBSCRIBE, '')

-- publishing to relay
local pub = ctx:socket(ZMQ.PUB)
pub:connect('tcp://*:65454')

--pub:send(('o'):rep(8192))
pub:send(('o'):rep(1024))

-- loop
local n = 0
local time = require('os').time
local t0 = time()
while true do
  local msg = sub:recv()
  pub:send(msg)
  n = n + 1
  if n % 10000 == 0 then
    print((time() - t0) / n, n, #msg)
  end
end
