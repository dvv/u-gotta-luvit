local String = require('lib/util')

local function test1()

  local foo = 'Привет Мир!'
  local fooh = foo:tohex()
  local foo1 = fooh:fromhex()
  p(foo, fooh, foo1, foo == foo1)

end

local function test2(x)

  print('Привет ${user}!' % {
    user = function() return x or 'Мир' end
  })
  

end

test1()
test2('foo') test2()
