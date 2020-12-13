local unpack = table.unpack or _G.unpack
local bit = _G.bit or _G.bit32 or false

local tty = true
local version = _VERSION
local OS = "Unknown"

local haveffi, ffi = pcall(require, "ffi")
if haveffi then
	OS = ffi.os
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


if package and package.config and OS == "Unknown" then
	local s = package.config:sub(1,1)
	if s == "\\" then OS = "Windows" end
end

local loadstring = _G.loadstring or _G.load

if loadstring then
	local ok, v = pcall(loadstring("return 2 + 2"))
	if not ok or v ~= 4 then loadstring = false end
end

if not bit then
	pcall(function()
		bit = require('bit32')
	end)
end

if not bit and loadstring and version == "Lua 5.4" then
	bit = loadstring([===[
	return {
		lshift = function(a,b) return a << b end,
		arshift = function(a,b) return a >> b end,
		band = function(a,b) return a & b end,
		bor = function(a,b) return a | b end,
		bxor = function(a,b) return a ~ b end,
		bnot = function(a) return ~a end
	}
	]===])()
end

if not bit then
	bit = setmetatable({}, {__index = function()
		return function() error('bit32 library not available', 0) end
	end})
end

local setfenv = setfenv or function(fx, env)
	local idx = 1
	repeat
		local name = debug.getupvalue(fx, idx)
		if not name then
			break
		elseif name == "_ENV" then
			debug.upvaluejoin(fx, idx, function() return env end, 1)
			break
		end

		idx = idx + 1
	until false
	return fx
end



local function numToStr(n) return '' .. n end

if ('' .. 3.0)  ~= "3" then
	numToStr = function(n)
		local i, f = math.modf(n)
		if f == 0 then
			return "" .. i
		else
			return "" .. n
		end
	end
end

return {
	unpack = unpack,
	bit = bit,
	loadstring = loadstring,
	setfenv = setfenv,
	lua = version,
	tty = tty,
	os = OS,
	numToStr = numToStr,
	color = tty and (OS ~= "Windows" or (os and os.getenv and os.getenv("SHELL")))
}