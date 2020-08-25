local Value = require('ucl.value')
local argparse = require('ucl.argparse')

local ReturnCode_Ok = 0
local ReturnCode_Error = 1
local ReturnCode_Return = 2
local ReturnCode_Break = 3
local ReturnCode_Continue = 4

local unpack = table.unpack or _G.unpack

local function join(...)
	local lst = {}
	for _,v in ipairs({...}) do
		local s = v.string:gsub("^%s+", ""):gsub("%s+$", "")
		if #s > 0 then table.insert(lst, s) end
	end
	local str = table.concat(lst, " ")
	return Value.fromString(str)
end

local arrays = {
	exists = function(interp, key)
		local var = interp.variables[key.string]

		if var and var.array then
			return Value.True
		else
			return Value.False
		end
	end,
	get = function(interp, key)
		local var = interp.variables[key.string]
		if not var then
			var = {name=key, array={}}
			interp.variables[key.string] = var
		end
		if not var.array then
			error("variable isnt an array")
		end
		local result = {}
		for k,v in pairs(var.array) do
			table.insert(result, Value.fromString(k))
			table.insert(result, v)
		end
		return Value.fromList(result)
	end,
	names = function(interp, key)
		local var = interp.variables[key.string]
		if not var then
			var = {name=key, array={}}
			interp.variables[key.string] = var
		end
		if not var or not var.array then
			error("variable isnt an array")
		end

		local names = {}
		for k,_ in pairs(var.array) do table.insert(names, Value.fromString(k)) end
		return Value.fromList(names)
	end,
	set = function(interp, key, list)
		local args = list.list
		if #args%2 ~= 0 then
			error('list must have an even number of elements', 0)
		end

		local var = interp.variables[key.string]
		if not var then
			var = {name=key, array={}}
			interp.variables[key.string] = var
		end
		if not var.array then
			error("variable isnt an array", 0)
		end

		for i=1,#args,2 do
			var.array[args[i].string] = args[i+1]
		end
		return Value.none
	end,
	size = function(interp, key)
		local var = interp.variables[key.string]
		if not var then
			var = {name=key, array={}}
			interp.variables[key.string] = var
		end
		if not var or not var.array then
			error("variable isnt an array")
		end
		local n = 0
		for _,_ in pairs(var.array) do n = n + 1 end
		return Value.fromNumber(n)
	end,
}

local strings = {
	index = function(interp, str, idx)
		local i = idx.number + 1
		return str:sub(i, i)
	end,
	length = function(interp, str)
		return Value.fromNumber(#str.string)
	end,
	equal = function(interp, a, b)
		if a.string == b.string then
			return Value.fromNumber(1)
		else
			return Value.fromNumber(0)
		end
	end,
	match = function(interp, pattern, str)
		if string.match(pattern.string, str.string) then
			return Value.fromNumber(1)
		else
			return Value.fromNumber(0)
		end
	end,
	range = function(interp, str, a, b)
		local s = str.string
		local aa = a.string == "end" and #s - 1 or a.number
		local bb = b.string == "end" and #s - 1 or b.number
		return str:sub(aa + 1,bb + 1)
	end,
	compare = function(interp, a, b)
		local aa = a.string
		local bb = b.string
		if aa == bb then return Value.fromNumber(0)
		elseif aa > bb then return Value.fromNumber(1)
		else return Value.fromNumber(-1) end
	end,
}

local infos = {
	level = function(interp, ...)
		local args = argparse("info level ?levelNum?")(Value.fromString('level'), ...)
		return Value.fromNumber(interp.level)
	end,
	commands = function(interp, ...)
		local args = argparse("info commands ?pattern?")(Value.fromString('commands'), ...)
		local result = {}
		local t = interp.commands
		while t do
			for k,v in pairs(t) do
				table.insert(result, Value.fromString(k))
			end
			t = getmetatable(t)
			if t then t = t.__index end
		end
		return Value.fromList(result)
	end,
	exists = function(interp, name, ...)
		local args = argparse("info exists varName")(Value.fromString('commands'), name, ...)
		return interp.variables[name.string] and Value.True or Value.False
	end,
	vars = function(interp)
		local result = {}
		local t = interp.variables
		for k,v in pairs(t) do
			table.insert(result, Value.fromString(k))
		end
		return Value.fromList(result)
	end,
	script = function(interp)
		return Value.fromString('script')
	end,
	patchlevel = function(intep)
		return Value.fromNumber(7)
	end,
	body = function(interp, ...)
		local args = argparse("info body procname")(Value.fromString('body'), ...)
		local c = interp.commands[args.procname.string]
		if type(c) == "table" then
			return c.body
		else
			error('command "' .. args.procname.string .. '" is not a procedure', 0)
		end
	end,
	args = function(interp, ...)
		local args = argparse("info args procname")(Value.fromString('args'), ...)
		local c = interp.commands[args.procname.string]
		if type(c) == "table" then
			return c.args
		else
			error('command "' .. args.procname.string .. '" is not a procedure', 0)
		end
	end,
	globals = function(interp)
		local lst = {}
		for k,v in pairs(interp.globals) do
			table.insert(lst, v.name)
		end
		return Value.fromList(lst)
	end,
}

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

function builtin.puts(interp, ...)
	print(...)
end

local function reducer(f)
	return function(interp, ...)
		local va = {...}
		if #va == 0 then return Value.fromNumber(0) end
		if #va == 1 then return f(Value.fromNumber(0), va[1]) end

		local acc = va[1]
		for i=2,#va do
			acc = f(acc, va[i])
		end
		return acc
	end
end

builtin['+'] = reducer(function(a, b) return a + b end)
builtin['-'] = reducer(function(a, b) return a - b end)
builtin['*'] = reducer(function(a, b) return a * b end)
builtin['/'] = reducer(function(a, b) return a / b end)
builtin['%'] = reducer(function(a, b) return a % b end)

builtin['==']  = function(interp, a, b) return Value.fromBoolean(a == b) end

function builtin.array(interp, command, ...)
	local cmd = command.string
	if not arrays[cmd] then error("unknown array command: " .. cmd, 0) end
	return arrays[cmd](interp, ...)
end

function builtin.catch(interp, code, var)
	local ok, ret, retCode = pcall(interp.eval, interp, code)
	if ok then
		if var then interp.set(var, ret) end
		return Value.fromNumber(retCode or ReturnCode_Ok), ReturnCode_Ok
	elseif var then
		interp.set(var, Value.fromString(ret))
	end
	return Value.True
end

function builtin.concat(interp, ...)
	return join(...)
end

function builtin.join(interp, list, sep, ...)
	if not list or select('#', ...) > 0 then
		error('wrong # args: should be "join list ?joinString?"', 0)
	end
	local lst = {}
	for k,v in ipairs(list.list) do
		local s = v.string
		table.insert(lst, s)
	end
	local str = table.concat(lst, sep and sep.string or ' ')
	return Value.fromString(str)
end

function builtin.error(interp, code)
	if code then
		error(code.string, 0)
	else
		error('error', 0)
	end
end

function builtin.eval(interp, ...)
	local va = {...}

	if #va == 0 then
		error('wrong # args: should be "eval arg ?arg ...?"', 0)
	end
	local v
	if #va == 1 then
		v = va[1]
	else
		local args = {}
		for k,v in ipairs(va) do
			args[k] = v.string
		end
		local s = table.concat(args," ")
		v = Value.fromString(s) --Todo Make CompoundString
	end

	return interp:eval(v)
end

function builtin.uplevel(interp, level, ...)
	local va = {...}

	if not level then
		error('wrong # args: should be "uplevel ?level? ?arg ...?"', 0)
	end

	local v
	local target = interp
	local ups = 1

	if tonumber(level.string) ~= nil then
		for i=1,level.number do
			target = target.up
		end
	elseif level.string:sub(1,1) == "#" then
		local locate = tonumber(level.string:sub(2))
		if locate > target.level then error('bad level', 0) end
		while target.level > locate do
			if not target.up then error('bad level', 0) end
			target = target.up
		end
	else
		target = target.up
		table.insert(va, 1, level)
	end

	if #va == 1 then
		v = va[1]
	else
		local args = {unpack(va)}
		v = Value.fromList(args)
	end

	return target:eval(v)
end

function builtin.info(interp, command, ...)
	local cmd = command.string
	if not infos[cmd] then error("unknown info command: " .. cmd, 0) end
	return infos[cmd](interp, ...)
end


function builtin.expr(interp, ...)
	return interp:expr(join(...), interp)
end

function builtin.foreach(interp, var, list, body)


	local llist = list.list
	local vlist = var.list
	for k,v in ipairs(vlist) do
		if not interp.variables[v.string] then
			interp.set(v, Value.none)
		end
	end
	local ret, retCode

	for k=1,#llist do
		local v = llist[k]
		local tidx = (k - 1) % #vlist + 1
		local target = interp.variables[vlist[tidx].string]
		target.value = v

		if tidx == #vlist then
			ret, retCode = interp:eval(body)

			if retCode == ReturnCode_Break then
				break;
			elseif retCode == ReturnCode_Continue then
			elseif retCode == ReturnCode_Ok then
			elseif retCode == nil then
			else
				return ret, retCode
			end
		end
	end
end

function builtin.format(interp, format, ...)
	local s = {...}

	if not format then error('wrong # args: should be "format formatString ?arg ...?"', 0) end

	local idx = 1
	local kind = 0
	local result = format.string:gsub("(%%([0-9]-)(%$-)([%+%- 0#]*)([0-9%.%*]*)([hl]*)([bfduioxXcseEgG%%]))", function(fmt, i, d, f, p, m, t)
		local prefix = ''

		if fmt == "%%" then return '%' end



		if d == '$' then
			idx = tonumber(i)
			if kind == 1 then error('cannot mix "%" and "%n$" conversion specifiers', 0) end
			if idx > #s or idx < 1 then error('"%n$" argument index out of range', 0) end
			kind = 2
		else
			if kind == 2 then error('cannot mix "%" and "%n$" conversion specifiers', 0) end
			kind = 1
		end


		if idx > #s then error('not enough arguments for all format specifiers', 0) end

		if p == "*" then
			p = s[idx].string
			idx = idx + 1
			if idx > #s or idx < 1 then
				if kind == 2 then
					error('"%n$" argument index out of range', 0)
				else
					error('not enough arguments for all format specifiers', 0)
				end
			end
		end

		local v = s[idx].string
		idx = idx + 1

		if t == 'b' then
			t = 's'
			v = string.format('%o', v):gsub('.', function(m)
				return ({'000','001','010','011','100','101','110','111'})[m + 1]
			end)
		end

		--print(fmt, idx, f .. p .. m .. t, v, f,p,m,t)
		return prefix .. string.format('%' .. f .. p .. t, v)
	end)

	return Value.fromString(result)
end

function builtin.global(interp, ...)
	for _, key in ipairs({...}) do
		if not interp.globals[key.string] then
			interp.globals[key.string] = {name=key, value=Value.none}
		end
		interp.variables[key.string] = interp.globals[key.string]
	end
end

builtin['if'] = function(interp, expr, thenword, body, elseword, ebody)
	if thenword and thenword.string ~= 'then' then
		body, elseword, ebody = thenword, body, elseword
	end

	if elseword and elseword.string ~= 'else' then
		ebody = elseword
	end

	if not body then
		error('wrong # args: no expression after "if" argument', 0)
	end

	local result = interp:expr(expr, interp)
	if result.number ~= 0 then
		return interp:eval(body)
	elseif ebody then
		return interp:eval(ebody)
	else
		return Value.none
	end
end

function builtin.incr(interp, key, amount)
	local dx = amount and amount.number or 1
	if not key then error('wrong # args: should be "incr varName ?increment?"', 0) end
	local v = interp.variables
	local s = key.string
	if s:sub(1,2) == "::" then
		v = interp.globals
		s = s:sub(3)
	end

	if not v[s] then
		local value = Value.fromNumber(dx)
		v[s] = {name=key, value=value}
		return value
	else
		local n = v[s].value.number
		n = n + dx
		local value = Value.fromNumber(n)
		v[s].value = value
		return value
	end
end

function builtin.lassign(interp, list, ...)
	local lst = list.list
	local va = {...}
	for k,v in ipairs(va) do
		if lst[k] then
			interp.set(v, lst[k])
		else
			interp.set(v, Value.none)
		end
	end
	return Value.none
end

function builtin.switch(interp, v, ...)
	local va = {...}
	local i = 1

	while i <= #va do
		if v == va[i] or v.string == 'default' then
			return interp:eval(va[i+1])
		end
		i = i + 2
	end
	return Value.none
end

function builtin.list(interp, ...)
	return Value.fromList({...})
end

local proc_mt = {
	__call = function(self, interp, ...)
		local state = interp:child()

		for k,v in ipairs(self.args.list) do
			local vv
			if v.string == "args" then
				local rest = Value.fromList({select(k, ...)})
				vv = rest
			else
				vv = select(k, ...)
			end
			rawset(state.variables, v.string, {name = v, value = vv})
		end
		local final, retCode = state:eval(self.body)
		return final, ReturnCode_Ok
	end
}

function builtin.proc(interp, name, args, body)
	interp.commands[name.string] = setmetatable({
		args = args,
		body = body
	}, proc_mt)
	return name
end

function builtin.rename(interp, from, to)
	if to.string ~= "" then
		interp.commands[to.string] = interp.commands[from.string]
	end
	interp.commands[from.string] = nil
end

function builtin.set(interp, key, value, ...)
	if not key or select('#', ...) > 0 then
		error('wrong # args: should be "set varName ?newValue?"', 0)
	end

	return interp.set(key, value)
end




function builtin.unset(interp, key)
	interp.variables[key.string] = nil
end

function builtin.range(interp, from, to, step)
	if not from then error('wrong # args: should be "range ?start? end ?step?"', 0) end
	if not to then
		to = from
		from = Value.fromNumber(0)
	end
	if not step then step = Value.fromNumber(1) end
	if step.number== 0 then error('Invalid (infinite?) range specified', 0) end
	local lst = {}
	for i=from.number, to.number, step.number do
		if i ~= to.number then
			table.insert(lst, Value.fromNumber(i))
		end
	end
	return Value.fromList(lst)
end


local function lidx(n, list)
	local s = n.string
	local a = s:match("^end([%+%-]-%--%d*)$")
	if a then
		if a == '' then
			return #list
		else
			return #list + tonumber(a)
		end
	end
	return n.number + 1
end

function builtin.lset(interp,name,idx,value)
	if not interp.variables[name.string] then
		error('unknown variable ' .. name.string, 0)
	end
	local var = interp.variables[name.string]
	local iidx = lidx(idx, var.value.list)
	--local iidx = idx.number + 1
	local result = {}
	if iidx < 1 then error('list index out of range', 0) end
	if iidx > #var.value.list then error('list index out of range', 0) end

	for k,v in ipairs(var.value.list) do
		if k == iidx then
			result[k] = value
		else
			result[k] = v
		end
	end

	var.value = Value.fromList(result)
	--print(#result, var.value.type, #var.value.list, var.value.string)
	return var.value
end

function builtin.lindex(interp, ...)
	local args = builtin.lindex.argparse(...)
	if not args.index then return args.list end
	local n = lidx(args.index, args.list.list)
	local v = args.list.list[n]
	if not v then return Value.none end
	return v
end
builtin.lindex.argparse = argparse("lindex list ?index?")

function builtin.linsert(interp, list, idx, ...)
	local ii = lidx(idx, list.list)
	local lst = {unpack(list.list)}
	for k,v in ipairs({...}) do
		table.insert(lst, ii + k, v)
	end
	return Value.fromList(lst)
end

function builtin.llength(interp, list)
	return Value:fromNumber(#list.list)
end

function builtin.string(interp, command, ...)
	local cmd = command.string
	if not strings[cmd] then error("unknown string command: " .. cmd, 0) end
	return strings[cmd](interp, ...)
end

builtin['return'] = function(interp, value)
	return (value or Value.none), ReturnCode_Return
end

builtin['while'] = function(interp, cond, body)
	local ret, retCode
	while interp:expr(cond, interp).number ~= 0 do
		ret, retCode = interp:eval(body)
		if retCode == ReturnCode_Break then
			break;
		elseif retCode == ReturnCode_Continue then
		elseif retCode == ReturnCode_Ok then
		elseif retCode == nil then
		else
			return ret, retCode
		end
	end
	return Value.none
end

builtin['for'] = function(interp, start, test, next, body)
	if not body then error('wrong # args: should be "for start test next body"', 0) end
	local ret, retCode
	interp:eval(start)
	while interp:expr(test).number ~= 0 do
		ret, retCode = interp:eval(body)
		if retCode == ReturnCode_Break then
			break;
		elseif retCode == ReturnCode_Continue then
		elseif retCode == ReturnCode_Ok then
		elseif retCode == nil then
		else
			return ret, retCode
		end
		interp:eval(next)
	end
	return ret
end

function builtin.append(interp, var, val)
	return interp.set(var, Value.fromCompoundList({interp.set(var), val}))
end

function builtin.lappend(interp, var, ...)
	if not var then error('wrong # args: should be "lappend varName ?value value ...?"', 0) end
	local v = interp.set(var)
	if not v then v = interp.set(var, Value.none) end
	local lst = {unpack(v.list)}
	for _,av in ipairs({...}) do table.insert(lst, av) end
	return interp.set(var, Value.fromList(lst))
end

function builtin.lsort(interp, list)
	local tosort = {unpack(list.list)}
	table.sort(tosort, function(a,b) return a.string < b.string end)
	return Value.fromList(tosort)
end

builtin['break'] = function(interp) return Value.none, ReturnCode_Break end
builtin['continue'] = function(interp) return Value.none, ReturnCode_Continue end

builtin['#'] = function(interp) return Value.none end

return builtin

