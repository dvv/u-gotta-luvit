local String = require('lib/string')

function test1()

  local foo = 'Привет Мир!'
  local fooh = foo:tohex()
  local foo1 = fooh:fromhex()
  p(foo, fooh, foo1, foo == foo1)

end

test1()
