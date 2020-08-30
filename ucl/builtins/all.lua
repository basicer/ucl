local env = require('ucl.env')
local Value = require('ucl.value')
local argparse = require('ucl.argparse')

local ReturnCode_Ok = 0
local ReturnCode_Error = 1
local ReturnCode_Return = 2
local ReturnCode_Break = 3
local ReturnCode_Continue = 4

local unpack = env.unpack

local command_mt = {
	__call = function(self, ...) return self.fx(...) end
}

local builtin = setmetatable({}, {
	__newindex = function(self, k, v)
		if type(v) == 'function' then
			rawset(self, k, setmetatable({
				fx = v
			}, command_mt))
		else
			rawset(self, k, v)
		end
	end
})


require('ucl.builtins.tcl')(builtin)

builtin['break'] = function(interp) return Value.none, ReturnCode_Break end
builtin['continue'] = function(interp) return Value.none, ReturnCode_Continue end

builtin['#'] = function(interp) return Value.none end

return builtin

