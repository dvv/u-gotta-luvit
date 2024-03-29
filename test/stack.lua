local Stack = require('lib/stack-1')
p(Stack)

function test1()

  -- test ok
  local stack = Stack({
    function (req, res, nxt)
      nxt()
    end,
    function (req, res, nxt)
      res.ok()
    end,
  })
  assert(stack.handler)
  local ok = false;
  stack.handler(nil, {ok = function() print('1. OK') end})

  -- test hard error
  stack.error_handler = function(req, res, err)
    print(err)
  end
  local stack = Stack({
    function (req, res, nxt)
      error('2. hard error OK')
    end,
    function (req, res, nxt)
      error('2. hard error NAK. never should be here')
    end,
  })
  stack.handler(nil, {send = function() end})

  -- test soft error
  local stack = Stack({
    function (req, res, nxt)
      nxt('3. soft error OK')
    end,
    function (req, res, nxt)
      res.send()
    end,
  })
  stack.handler(nil, {send = function(...) p('3. res.send', ...) end})

end

test1()
