-- these are required by ZMQ
bit = require('bit')
debug = require('debug')
local ZMQ = require('zmq')

-- context
local ctx = ZMQ.init(1)

local worker = {}

function worker:connect(relay_address, callback)
  self._hub = {
    sub = ctx:socket(ZMQ.SUB),
    pub = ctx:socket(ZMQ.PUB),
  }
  self._hub.sub:connect('tcp://localhost:65455')
  self._hub.sub:setopt(ZMQ.SUBSCRIBE, '')
  self._hub.pub:connect('tcp://localhost:65454')
  if callback then callback() end
  return self
end

function worker:broadcast(message)
  return self._hub.pub:send(message)
end

local function new()
  local instance = {}
  setmetatable(instance, {__index=worker})
  return instance
end

return {
  new = new
}
