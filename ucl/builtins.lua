local Value = require('ucl/value')

local ReturnCode_Ok = 0
local ReturnCode_Error = 1
local ReturnCode_Return = 2
local ReturnCode_Break = 3
local ReturnCode_Continue = 4

local function join(...)
	local lst = {}
	for k,v in ipairs({...}) do
		lst[k] = v.string
	end
	local str = table.concat(lst, " ")
	return Value.fromStringView(str, 0, #str)
end

local strings = {
	index = function(interp, str, idx)
		local i = idx.number + 1
		return str:sub(i, i)
	end,
	length = function(interp, str)
		return Value.fromNumber(#str.string)
	end
}

return {
	puts = function(interp, ...)
		print(...)
	end,

	['+'] = function(interp, a, b) return a + b end,
	['-'] = function(interp, a, b) return a - b end,
	['*'] = function(interp, a, b) return a * b end,
	['/'] = function(interp, a, b) return a / b end,
	['==']  = function(interp, a, b) return Value.fromBoolean(a == b) end,

	concat = function(interp, ...)
		return join(...)
	end,

	eval = function(interp, ...)
		local va = {...}

		if #va == 0 then
			error('wrong # args: should be "eval arg ?arg ...?"', 0)
		end
		local args = {}
		for k,v in ipairs(va) do
			args[k] = v.string
		end
		local s = table.concat(args," ")
		return interp.eval(Value.fromStringView(s,0,#s))
	end,

	error = function(interp, code)
		error(code.string, 0)
	end,

	expr = function(interp, ...)
		return interp.expr(join(...), interp)
	end,

	foreach = function(interp, var, list, body)
		if not interp.variables[var.string] then
			interp.variables[var.string] = {name=var, value=Value.none}
		end
		
		local target = interp.variables[var.string]

		local llist = list.list

		for k,v in ipairs(llist) do
			target.value = v
			interp.eval(body)
		end
	end,

	['if'] = function(interp, expr, thenword, body, elseword, ebody)
		if thenword and thenword.string ~= 'then' then
			body, elseword, ebody = thenword, body, elseword
		end

		if elseword and elseword.string ~= 'else' then
			ebody = elseword
		end

		if not body then
			error('wrong # args: no expression after "if" argument', 0)
		end

		local result = interp.expr(expr, interp)
		if result.number ~= 0 then
			return interp.eval(body)
		elseif ebody then
			return interp.eval(ebody)
		else
			return Value.none
		end
	end,

	list = function(interp, ...)
		return Value.fromList({...})
	end,

	proc = function(interp, name, args, body)
		interp.commands[name.string] = function(interp, ...)
			local state = interp:child()

			for k,v in ipairs(args.list) do
				if v.string == "args" then
					local rest = Value.fromList({select(k, ...)})
					state.variables[v.string] = {name=v, value=rest}
				else
					state.variables[v.string] = {name=v, value=select(k, ...)}
				end
			end
			local final, retCode = state.eval(body)
			return final, ReturnCode_Ok
		end
		return name
	end,

	format = function(interp, format, ...) 
		return format
	end,

	set = function(interp, key, value)
		if not interp.variables[key.string] then
			interp.variables[key.string] = {name=key, value=value}
			return value
		elseif value then
			interp.variables[key.string].value = value
			return value
		else
			return interp.variables[key.string].value
		end
	end,
	incr = function(interp, key, amount)
		local dx = amount and amount.number or 1

		if not interp.variables[key.string] then
			local value = Value:fromNumber(amount)
			interp.variables[key.string] = {name=key, value=value}
			return value
		else
			local n = interp.variables[key.string].value.number
			n = n + dx
			local value = Value.fromNumber(n)
			interp.variables[key.string].value = value
			return value
		end
	end,
	unset = function(interp, key) 
		interp.variables[key.string] = nil
	end,
	global = function(interp, ...)
		for _, key in ipairs({...}) do
			if not interp.globals[key.string] then
				interp.globals[key.string] = {name=key, value=Value.fromStringView("", 0, 0)}
			end
			interp.variables[key.string] = interp.globals[key.string]
		end
	end,
	catch = function(interp, code, var)
		local ok, ret, retcode = pcall(interp.eval, code)
		if ok then
			return ret, retcode
		elseif var then
			interp.variables[var.string] = {
				name=var.string,
				value=Value.fromString(ret)
			}
		end
		return Value.fromNumber(1)
	end,
	llength = function(interp, list)
		return Value:fromNumber(#list.list)
	end,
	string = function(interp, command, ...)
		local cmd = command.string
		if not strings[cmd] then error("unknown string command: " .. cmd, 0) end
		return strings[cmd](interp, ...)
	end,

	['return'] = function(interp, value)
		return (value or Value.none), ReturnCode_Return
	end,

	['#'] = function(inter, value) end
}

