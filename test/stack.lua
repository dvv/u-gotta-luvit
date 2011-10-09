local Stack = require('lib/stack')

function test1()

  -- test ok
  local stack = Stack.create({
    function (req, res, nxt)
      nxt()
    end,
    function (req, res, nxt)
      res.ok()
    end,
  })
  local ok = false;
  stack(nil, {ok = function() print('1. OK') end})

  -- test hard error
  Stack.error_handler = function(req, res, err)
    print(err)
  end
  local stack = Stack.create({
    function (req, res, nxt)
      error('2. hard error OK')
    end,
    function (req, res, nxt)
      res.ok()
    end,
  })
  stack(nil, nil)

  -- test soft error
  local stack = Stack.create({
    function (req, res, nxt)
      nxt('3. soft error OK')
    end,
    function (req, res, nxt)
      res.ok()
    end,
  })
  stack(nil, nil)

end

test1()
