local debug = require('debug')
print(debug.getinfo(1).short_src)

require.path = require.path .. ''

require('module1')

print(foo, bar)
