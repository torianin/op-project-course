// Use the original vendored compiler to preserve CoffeeScript 1.x semantics.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const compiler = path.join(root, 'vendor/bundle/ruby/1.9.1/gems/coffee-script-source-1.6.2/lib/coffee_script/coffee-script.js');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(compiler, 'utf8'), context);
const source = fs.readFileSync(path.join(root, 'views/application.coffee'), 'utf8');
const compiled = context.CoffeeScript.compile(source);
fs.writeFileSync(path.join(root, 'public/application.js'), compiled);
console.log('Compiled public/application.js');
