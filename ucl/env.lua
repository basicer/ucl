local unpack = table.unpack or _G.unpack
local bit = _G.bit or _G.bit32 or false

local tty = true
local version = _VERSION
local os = "Unknown"

local haveffi, ffi = pcall(require, "ffi")
if haveffi then
	os = ffi.os
	version = version:gsub("Lua", "Lua (jit)")
	ffi.cdef [[
		 int isatty(int fd);
	]]
	pcall(function()
		tty = 1 == ffi.C.isatty(1)
	end)
end

local havejit, jit = pcall(require, "jit")
if havejit then
	version = jit.version or version
end

if not bit then
	pcall(function()
		bit = require('bit32')
	end)
end

if not bit then
	bit = setmetatable({}, {__index = function()
		return function() error('bit32 library not available', 0) end
	end})
end

local loadstring = _G.loadstring or _G.load

if loadstring then
	local ok, v = pcall(loadstring("return 2 + 2"))
	if not ok or v ~= 4 then loadstring = false end
end

local setfenv = setfenv or function(fx, env)
	local idx = 1
	repeat
		local upvalue = debug.getupvalue(fx, idx)
		if not name then
			break
		elseif name == "__ENV" then
			debug.upvaluejoin(fx, idx, function() return env end, 1)
			break
		end
		
		idx = idx + 1
	until false
	return f
end

local function colorize(fmt, ...)
	local text = fmt:gsub("{([^}]+)}", function(k)
		local codes = {
			['normal'] = "\027[0",
			['bold']   = "\027[1",
			['dim']    = "\027[2",
			['i']      = "\027[3",
			['u']      = "\027[4",
			['blink']  = "\027[5",
			['inverse']= "\027[7",

			['black-fg']   = "\027[30m",
			['red-fg']     = "\027[31m",
			['green-fg']   = "\027[32m",
			['yellow-fg']  = "\027[33m",
			['blue-fg']    = "\027[34m",
			['magenta-fg'] = "\027[35m",
			['cyan-fg']    = "\027[36m",
			['white-fg']   = "\027[37m",
			['default-fg'] = "\027[37m",

			['black-bg']   = "\027[40m",
			['red-bg']     = "\027[41m",
			['green-bg']   = "\027[42m",
			['yellow-bg']  = "\027[43m",
			['blue-bg']    = "\027[44m",
			['magenta-bg'] = "\027[45m",
			['cyan-bg']    = "\027[46m",
			['white-bg']   = "\027[47m",
			['default-bg'] = "\027[47m",

			['/'] =  "\027[0m"
		}
		if tty and os ~= "Windows" then
			return codes[k]
		elseif codes[k] then
			return ''
		end
	end):format(...)
	if tty and os ~= "Windows" then
		return text .. "\027[0m"
	else
		return text
	end
end

return {
	unpack = unpack,
	bit = bit,
	loadstring = loadstring,
	setfenv = setfenv,
	lua = version,
	colorize = colorize,
	tty = tty,
	os = os
}