
setmetatable(_G, {
	__newindex = function(_, name) error("No such global:" .. name) end,
	index = function(_, name) error("No such global:" .. name) end,
})

local Value = require('ucl.value')
local Engine = {}

local env = require('ucl.env')
local unpack = env.unpack

local ReturnCode_Ok = 0
local ReturnCode_Error = 1
local ReturnCode_Return = 2
local ReturnCode_Break = 3
local ReturnCode_Continue = 4

local globals = {}

local builtins = require('ucl.builtins.all')


local function x(v, state)
	if v.type == "CList" then
		return state:eval(v)
	else
		return v:interp(state)
	end
end

local function ucl_var(interp, k)
	local va, vb = k:find("%(.*%)$")
	if va then
		local idx = k:sub(va+1, vb-1)
		local n = k:sub(1, va-1)
		if not interp.variables[n] then
			interp.variables[n] = {name=Value.fromString(k), array={}}
		end
		return interp.variables[n].array[idx]
	end

	local vref
	repeat
		vref = interp.variables[k]
		if vref and vref.deleted then interp.variables[k] = nil end
	until not vref or not vref.deleted

	return vref
end

local function ucl_set(interp, key, value)
	local k = key.string
	local va, vb = k:find("%(.*%)$")
	if va then
		local idx = k:sub(va+1, vb-1)
		local n = k:sub(1, va-1)
		if not interp.variables[n] then
			interp.variables[n] = {name=Value.fromString(k), array={}}
		end
		if value then
			interp.variables[n].array[idx] = {name=Value.fromString(idx), value=value}
		end
		local vidx = interp.variables[n].array[idx]
		if vidx then return vidx.value else return Value.none end
	end

	local vref
	repeat
		vref = interp.variables[k]
		if vref and vref.deleted then interp.variables[k] = nil end
	until not vref or not vref.deleted

	if not vref then
		interp.variables[k] = {name=key, value=value}
		return value
	elseif value then
		vref.value = value
		return value
	else
		return vref.value
	end
end

local function ucl_eval(code, state)
	local out, retCode

	if type(code) ~= "table" then
		if #code > 0 then
			code = Value.fromStringView(code, 1, #code)
		else
			code = Value.none
		end
	end
	if state.flags.jit > 0 and env.loadstring then
		local n = rawget(code, "cnt") or 1
		rawset(code, "cnt", n + 1)
		if n >= state.flags.jit then return code.execute(state) end
	end
	for _,v in pairs(code.cmdlist) do
		local lst = v.list
		local mapped = {}

		local c = x(lst[1], state)
		if c.string:sub(1,1) ~= "#" then

			local cmd = state.commands[c.string]
			if not cmd and state.commands.unknown then
				cmd = function(self, ...) return state.commands.unknown(self, c, ...) end
			end
			if not cmd then
				if rawget(c, 'string_view') then
					local off =  c.string_view[2]
					local st = c.string_view[1]
					local line = 1
					local col = 0
					for i=1,off do
						if st:sub(i,i) == '\n' then
							col = 0 line = line + 1
						else
							col = col + 1
						end
					end

					error("Invalid Command: " .. c.string .. ' at ' .. line .. ':' .. col, 0)
				else
					error("Invalid Command: " .. c.string, 0)
				end
			end

			for i=2,#lst do
				mapped[i-1] = x(lst[i], state)
			end

			--local s = lst[1].string
			--for k,v in pairs(mapped) do s = s .. ',' .. v.string end
			--print("TRACE", s, unpack(mapped))

			out, retCode = cmd(state, unpack(mapped))
			retCode = retCode or ReturnCode_Ok

			if retCode ~= ReturnCode_Ok then
				return out, retCode
			end
		end
	end
	return out, ReturnCode_Ok
end

local expr = require('ucl.expr')
local ucl_expr = function(code, state)
	return Value.from(expr.expr(code, state))
end

local function newstate(engine)
	local state = {
		commands = engine.commands,
		engine = engine,
		variables = globals,
		globals = globals,
		level = 0,
		flags = engine.flags,
		print = engine.print
	}
	state.set = function(...) return ucl_set(state, ...) end
	state.var = function(...) return ucl_var(state, ...) end
	state.eval = function(s, code) return ucl_eval(code, s) end
	state.expr = function(s, code) return ucl_expr(code, s) end
	state.child = function(self)
		local cmds
		if next(self.commands) ~= nil then
			cmds = setmetatable({}, {__index = self.commands})
		else
			cmds = setmetatable({}, getmetatable(self.commands))
		end

		local c = {
			globals = self.globals,
			level = self.level + 1,
			commands = cmds,
			engine = self.engine,
			variables = setmetatable({}, {__index = self.globals}),
			child = self.child,
			flags = self.flags,
			up = self,
			print = self.print
		}
		c.eval = function(s, code) return ucl_eval(code, s) end
		c.expr = function(s, code) return ucl_expr(code, s) end
		c.set = function(...) return ucl_set(c, ...) end
		c.var = function(...) return ucl_var(c, ...) end
		return c;
	end
	return state
end

function Engine:eval(code, state)
	state = state or newstate(self)
	return state:eval(code)
end

function Engine:interactive()
	return require('ucl.interactive').new(self)
end

function Engine:state()
	return newstate(self)
end

function Engine.new()
	return setmetatable({
		commands = setmetatable({}, {__index = builtins}),
		globals = {},
		flags = {jit = 0},
		print = print
	}, {
		__index = Engine
	})
end

Engine.Value = Value

return Engine