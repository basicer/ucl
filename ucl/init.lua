
setmetatable(_G, {
	__newindex = function(g, name) assert("No such global:" .. name) end,
	index = function(g, name) assert("No such global:" .. name) end,
})

local Value = require('ucl/value')
local Engine = {}

local unpack = _G.unpack or table.unpack

local ReturnCode_Ok = 0
local ReturnCode_Error = 1
local ReturnCode_Return = 2
local ReturnCode_Break = 3
local ReturnCode_Continue = 4

local globals = {}

local builtins = require('ucl/builtins')



local function ucl_eval(code, state)
	local out, retCode

	if type(code) ~= "table" then
		code = Value.fromStringView(code, 0, #code)
	end

	for _,v in pairs(code.cmdlist) do
		local lst = v.list
		local mapped = {}

		local cmd = state.commands[lst[1].string]
		if not cmd then
			if rawget(lst[1], 'string_view') then
				local off =  lst[1].string_view[2]
				local st = lst[1].string_view[1]
				local line = 1
				local col = 0
				for i=1,off do
					if st:sub(i,i) == '\n' then
						col = 0 line = line + 1
					else
						col = col + 1
					end
				end

				error("Invalid Command: " .. lst[1].string .. ' at ' .. line .. ':' .. col)
			else
				error("Invalid Command: " .. lst[1].string)
			end
		end

		for i=2,#lst do
			if lst[i].type == "CList" then
				mapped[i-1] = state.eval(lst[i], state)
			else
				mapped[i-1] = lst[i]:interp(state.variables)
			end
		end
		local s = lst[1].string
		for k,v in pairs(mapped) do s = s .. ',' .. v.string end
		out, retCode = cmd(state, unpack(mapped))

		if retCode == ReturnCode_Return then
			return out, retCode
		end
	end
	return out
end

function Engine:eval(code, state)
	state = state or self:state()
	return ucl_eval(code, state)

end

local function ucl_expr(code, state)
	if type(code) ~= "table" then
		code = Value.fromStringView(code, 0, #code)
	end
	local lst = code.list
	if #lst == 1 then return lst[1] end
	if #lst ~= 3 then error("Invalid expr, len:" .. #lst) end
	return state.commands[lst[2].string](state, lst[1],lst[3])
end

function Engine:state() 
	local state = {
		commands = self.commands,
		engine = self,
		variables = globals,
		globals = globals,
	}
	state.eval = function(code, s) return ucl_eval(code, s or state) end
	state.expr = function(code, s) return ucl_expr(code, s or state) end
	state.child = function(self)
		local c = {
			globals = self.globals,
			commands = setmetatable({}, {__index = self.commands}),
			engine = self.engine,
			variables = setmetatable({}, {__index = self.variables}),
			child = self.child,
		}
		c.eval = function(code, s) return ucl_eval(code, s or c) end
		c.expr = function(code, s) return ucl_expr(code, s or c) end
		return c;
	end
	return state
end

function Engine.new()
	return setmetatable({
		commands = setmetatable({}, {__index = builtins}),
		globals = {}
	}, {
		__index = Engine
	})
end

Engine.Value = Value

return Engine