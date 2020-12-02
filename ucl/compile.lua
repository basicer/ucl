-- luacheck: max line length 240

local LuaWriter_mt = {}
local INDENT = "    "
local function LuaWriter()
    return setmetatable({
        indent = "",
        parts = {},
        needsIndent = true,
        hoisted = {}
    }, {__index=LuaWriter_mt})
end

function LuaWriter_mt:toString()
    return table.concat(self.parts, '')
end

function LuaWriter_mt:hoist(s, val)
    local idx = #self.hoisted+1

    if val then
        local sv = val.string
        if #sv < 10 and false then
            self.hoisted[idx] = 'Value.fromString(' .. string.format("%q", sv) .. ')'
        else
            self.hoisted[idx] = s .. ' --[====[' .. sv .. ']====]--'
        end
    else
        self.hoisted[idx] = s
    end
    return "hoisted[" .. idx .. "]"
end

function LuaWriter_mt:line(s)
    self:write(s)
    self:endl()
end

function LuaWriter_mt:endl()
    self:write("\n")
    self.needsIndent = true
end

function LuaWriter_mt:write(s)
    if self.needsIndent then
        table.insert(self.parts, self.indent)
        self.needsIndent = false
    end
    table.insert(self.parts, s)
end

function LuaWriter_mt:import(s)
   for line in string.gmatch(s,'[^\r\n]+') do
        self:line(line)
    end
end


function LuaWriter_mt:fx(...)
    self:write("function(")
    local args = {...}
    for i=1,#args-1 do
        if i ~= 1 then self:write(",") end
        self:write(args[i])
    end
    self:write(")")
    self:write("\n")
    local i = self.indent
    self.indent = self.indent .. INDENT
    self:write(self.indent)
    args[#args](self)
    self.indent = i
    self:line("end")
end

function LuaWriter_mt:i(f)
    local i = self.indent
    self.indent = self.indent .. INDENT
    f()
    self.indent = i
end

function LuaWriter_mt:doend(fx)
    self:line("do")
    local i = self.indent
    self.indent = self.indent .. INDENT
    fx(self)
    self.indent = i
    self:line("end")
end

local function q(s)
    if true then
        return string.format("%q", s)
    else
        return '([===[' .. s .. ']===])'
    end
end

function LuaWriter_mt:string(s)
    if true then
        self:write(q(s))
    else
        self:write("([==[")
        self:write(s)
        self:write("]==])")
    end
end

local function wv(w, v)
    w:write(w:hoist('Value.fromString(' .. q(v.string) .. ')'))
end

local cmd, fx
local function interp(w, v, origin)
    if v.type == "RawString" then
        wv(w, v)
        w:write(", 0")
    elseif v.type == "CList" then
        w:write("(")
       fx(w, v, origin)
        w:write(")(interp)")
    elseif v.type == "CString" then
        w:write("(")
        w:fx(function()
            w:line("local ret, retCode")
            w:line("local o = {}")
            for i=1,#v.parts do
                w:write("ret, retCode = ")
                interp(w, v.parts[i], origin .. '.parts[' .. i .. ']')
                w:line()
                w:line("if retCode ~= 0 and retCode ~= nil then return ret, retCode end")
                w:line("o[" .. i .. "] = ret")
            end
            if v.seperator == "" then
                w:line('return Value.fromCompoundList(o), retCode')
            else
                w:line('return Value.fromCompoundList(o,' .. q(v.seperator) .. '), retCode')
            end
        end)
        w:write(")()")
    elseif v.type == "Variable" then
        local o = v.string:sub(2)
        o = o:gsub("(%b{})", function(s) print(o, s:sub(2,-2)) return s:sub(2,-2) end)
        w:write("interp.variables['" .. o .. "'] and interp.variables['" .. o .. "'].value or Value.fromString('?" .. o .. "?')")
    else
        wv(w, v)
        w:write(':interp(interp), 0')
    end
end

local special = {}

local function fargs(w, v, origin)
    w:line("args = {}")
    local args = {}
    for i=1,#v.list do
        local vv = v.list[i]
        if vv.type ~= "RawString" then
            w:write("args[" .. i .. "], retCode = ")
            interp(w, vv, origin .. '.list[' .. i .. ']')
            w:line()
            w:line("if retCode ~= 0 and retCode ~= nil then return args[" .. i .. "], retCode end")
            w:line()
            args[i] = {v = "args[" .. i .. "]", s = "args[" .. i .. "].string", a = vv}
        else
            --args[i] = { v = w:hoist('Value.fromString([===[' .. vv.string .. ']===])'), s = '([===[' .. vv.string .. ']===])'  }
            local h = w:hoist(origin .. '.list[' .. i .. ']', vv)
            args[i] = { v = h, s = q(vv.string), a = vv  }
        end
    end
    return args
end

local fallback =  function(w, args)
    w:line("if not cmd and interp.commands.unknown then")
    w:line("    cmd = function(self, ...) return interp.commands.unknown(self, " .. args[1].v .. ", ...) end")
    w:line("end")
    w:line("if not cmd then error('No such command: ' .. " .. args[1].s .. ", 0) end")

    w:write("ret,retCode = cmd(interp")
    for i=2,#args do
        w:write(", ")
        w:write(args[i].v)
    end
    w:write(")")
    w:line()

    w:line("if retCode ~= 0 and retCode ~= nil then return ret, retCode end")
    w:line()
end

cmd = function(w, v, origin)
    if v.list[1].string:sub(1,1) == "#" then
        return
    end

    w:line("-- origin: " .. origin)
    local args = fargs(w, v, origin)
    w:line("cmd = interp.commands[" .. args[1].s .. "]")

    if v.list[1].type == "RawString" then
        local s = v.list[1].string

        if special[s] then
            local sw = LuaWriter()
            sw.hoisted = w.hoisted

            if special[v.list[1].string](sw, v, origin, args) then
                w:line("-- Special implementaton for " .. s)
                w:line("if cmd.builtin == " .. q(s) .. " then")
                w:i(function() w:import(sw:toString()) end)
                w:line("else")
                w:i(function() fallback(w, args) end)
                w:line("end")
                return
            end
        end
    end


    fallback(w, args)
end

fx = function(wx, s, origin)
    wx:fx("interp", function (w)
        w:line('local ret, retCode, args, cmd, sk = Value.none, 0')
        for k,v in pairs(s.cmdlist) do
            cmd(w, v, origin .. ".cmdlist[" .. k .. "]")
        end
        w:line("return ret, retCode")
    end)
end

local function compile(s)
    local ww = LuaWriter()

    ww:write("return ")
    ww:fx("origin", "Value", function(w)
        local w2 = LuaWriter()
        w2.indent = w.indent
        fx(w2, s, 'origin')
        w:line("local hoisted = {}")
        for k,v in pairs(w2.hoisted) do
            w:line("hoisted[" .. k .. "] = " .. v)
        end
        w:write("return ")
        w:write(w2:toString())
    end)

    local result = ww:toString()
    --io.stderr:write(result)
    return result
end


local function ep(w, t)
    if type(t) == 'table' then
        if t.type == "variable" then
            w:write('(interp.variables[')
            w:string(t.name)
            w:write('] or error("no such variable ' .. t.name .. '", 0)).value.number')
        elseif t.type == "cmd" then
            local root = w:hoist('Value.fromString(' .. q(t.value.string) .. ')', t.value)
            interp(w, t.value, root)
            w:write(".number")
        end
    else
        w:write(t)
    end
end

local function expr(w, whats)
    local ops = { ['+']= '+', ['-'] = '-', ['*']= '*', ['/'] = '/' }
    repeat
        if whats.a.type ~= "RawString" then break end

        local tokens = whats.a.expr_tokens
        w:write("--[[ #T:" .. #tokens .. "]] ")
        if #tokens == 1 then
            if tostring(tokens[1]):match("^%d$") then
                w:write(whats.v)
            else
                w:write("Value.fromNumber(")
                ep(w, tokens[1])
                w:write(")")
            end
            return
        end
        if #tokens ~=3 then break end
        local op = tokens[2]

        if op == "<" or op == '>' or op == "==" or op == "!=" then
            if op == "!=" then op = "~=" end
            w:write("(")
            ep(w, tokens[1])
            w:write(op)
            ep(w, tokens[3])
            w:write(") and Value.True or Value.False")
        elseif ops[op] then
            w:write("Value.fromNumber(")
            ep(w, tokens[1])
            w:write(ops[op])
            ep(w, tokens[3])
            w:write(")")
        else
            break
        end

        return
    until true


    w:write("interp:expr(" .. whats.v .. ")")
end

-- luacheck: push no unused args

special['return'] = function(w, v, origin)
    if #v.list ~= 2 then return false end
    local args = fargs(w, v, origin)
    w:line("-- return " .. args[2].s)
    w:write("if true then return ")
    w:write(args[2].v)
    w:line(", 2 end")
    return true
end

special['if'] = function(w, v, origin, args)

    if #v.list ~= 3 and not (#v.list == 5 and v.list[4].string == "else") then
        return false
    end

    w:line("-- if " .. args[2].s)

    w:write("ret = ")
    expr(w, args[2])
    w:line()

    w:line("if ret.number ~= 0 then")
    local i = w.indent
    w.indent = w.indent .. INDENT
    for k, vv in pairs(v.list[3].cmdlist) do
        cmd(w,vv, origin .. '.list[3].cmdlist[' .. k .. ']')
    end
    if #v.list == 5 then
        w.indent = i
        w:line("else")
        w.indent = w.indent .. INDENT
        for k, vv in pairs(v.list[5].cmdlist) do
            cmd(w, vv, origin .. '.list[5].cmdlist[' .. k .. ']')
        end
    end
    w.indent = i
    w:line("end")
    return true
end

special['expr'] = function(w, v, origin, args)
    if #v.list ~= 2 then return false end
    w:write("ret = ")
    expr(w, args[2])
    w:line()
    return true
end

special['puts'] = function(w, v, origin, args)

    w:write("interp.print(")
    for i=2,#args do
        if i ~= 2 then w:write(",") end
        w:write(args[i].s)
    end
    w:write(")")
    w:line()
    w:line("ret, retCode = Value.none, 0")
    return true
end

-- luacheck: pop

return compile