local mime = require('lib/mime').by_filename

assert(mime('.aa.bb.cc.dd.js') == 'application/javascript')
assert(mime('Привет.Солнечный.Мир.Css') == 'text/css')
require('lib/mime').table.default = 'foo/bar'
assert(mime('Привет.Солнечный.Мир') == 'foo/bar')
