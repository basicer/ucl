local i = require('ucl')
local Value = require('ucl.value')
local env = require('ucl.env')

local ValueType_None   = 0
local ValueType_Number = 1
local ValueType_String = 2
local ValueType_RawString = 3
local ValueType_List = 4
local ValueType_CommandList = 5
local ValueType_CompoundString = 6
local ValueType_Variable = 7



local parseExpression

local function ws(s)
    s:consumep("%s+")
end

local function parseIdentifier(s)
    ws(s)
    return s:consumep("[a-zA-Z][a-zA-Z0-9]*")
end

local function parseValue(s)
    local z
    ws(s)
    z = s:consumep("[0-9][0-9.]*")
    if z then
        print("Parsed", z)
        return z
    end

    z = s:consumep('"[^"]*"')
    if z then
        return Value.fromString(z.string:sub(2,-2)) --todo: stringview
    end

    z = parseIdentifier(s)
    if z then
        if s:consumep("%s*%(") then
            local cl = {z}
            if not s:consumep("%s*%)") then
                while true do
                    local m = parseExpression(s)
                    if not m then
                        error("Expected an expression", 0)
                    end
                    ws(s)
                    table.insert(cl, m)
                    if s:consumep("%)") then break
                    elseif s:consumep(",") then
                    else
                        error("Expected , or ) to continue arguement list, found " .. s:peek(), 0)
                    end
                end
            end
            return Value.fromCmdList({Value.fromList(cl)})
        end
        print("Var", z.string)
        return Value.fromStringView('$' .. z.string, 1, #z.string + 1, ValueType_Variable)
    end
    return false
end

parseExpression = function(s)
    local l = {Value.fromString('expr'), parseValue(s)}
    if not l[1] then return false end
    while true do
        local o = s:consumep("[+%*/-=><]")
        if not o then break end
        print("Parsed", o)
        local r = parseValue(s)
        table.insert(l, o)
        table.insert(l, r)
    end

    if #l == 2 then return l[2] end
    return Value.fromCmdList({Value.fromList(l)})
end
local parseStatementOrBlock
local function parseStatement(s)
    ws(s)
    if s:consumep("if") then
        if not s:consumep("%s*%(") then error('expected ( after if', 0) end
        local cond = parseExpression(s)
        if not cond then error('expected expression after (', 0) end
        if not s:consumep("%s*%)") then error('expected ) after if condition', 0) end
        ws(s)
        local yes = parseStatementOrBlock(s);
        local no
        if not yes then error('expected statement after if, found ' .. s:peek(), 0) end
        if s:consumep("%s*else%s*") then
            no = parseStatementOrBlock(s)
        end
        local lst = cond
        if cond.kind == ValueType_CommandList and cond.cmdlist[1].list[1].string == 'expr' then
            lst = {env.unpack(cond.cmdlist[1].list)}
            table.remove(lst, 1)
            lst = Value.fromList(lst)
        end
        local ll = {Value.fromString("if"), lst, yes}
        if no then
            table.insert(ll,Value.fromString("else"))
            table.insert(ll, no)
        end
        return Value.fromList(ll)
    end

    local z = parseExpression(s)
    if not z then return false end

    if z.kind == ValueType_CommandList then
        z = z.cmdlist[1]
    end

    return z
end


local function parseBlock(s)
    local l = {}
    while true do
        local z = parseStatement(s)
        if not z then break end
        table.insert(l,z)
    end
    local o = Value.fromCmdList(l)
    rawset(o, 'kind', ValueType_RawString)
    rawset(o, 'string', false)
    return o
end

parseStatementOrBlock = function(s)
    ws(s)
    if s:consumep("{") then
        local r = parseBlock(s)
        if not s:consumep("}") then error('Expected } to end block', 0) end
        return r
    else
        local l = parseStatement(s)
        if not l then return false end
        local o = Value.fromCmdList({l})
        rawset(o, 'kind', ValueType_RawString)
        return o
    end
end

local o = [[

puts(3, 2+2, llength("tacos are yummy"), var)
puts(3*3)
puts(llength("tacos are yummy")*var)

if (var>8) {
    puts("yes")
    puts("no")
    if (0) {
        puts("never")
    } else if (1) {
        puts(1)
    } else {
        puts(2)
    }
}

]]

local v = Value.fromString(o)
local s = v:scanner()
local e = parseBlock(s)
print()
print()
print(e.code)
print()
print()

local a,b = pcall(function()


    local tcl = i.new()
    tcl:eval("set var 10")
    local a,b = tcl:eval(e)
    print("R",a,b)

end)

print(a,b)
print('done')