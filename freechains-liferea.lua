#!/usr/bin/env lua5.3

local socket = require 'socket'

local HASH_BYTES = 32

local url = assert((...))

--local log = assert(io.open('/tmp/log.txt','a+'))
local log = io.stderr
log:write('URL: '..url..'\n')

if string.sub(url,1,13) ~= 'freechains://' then
    os.execute('xdg-open '..url)
    os.exit(0)
end

local function ASR (cnd, msg)
    msg = msg or 'malformed command'
    if not cnd then
        io.stderr:write('ERROR: '..msg..'\n')
        os.exit(1)
    end
    return cnd
end

FC = {}
function FC.hash2hex (hash)
    local ret = ''
    for i=1, string.len(hash) do
        ret = ret .. string.format('%02X', string.byte(string.sub(hash,i,i)))
    end
    return ret
end
function FC.escape (html)
    return (string.gsub(html, "[}{\">/<'&]", {
        ["&"] = "&amp;",
        ["<"] = "&lt;",
        [">"] = "&gt;",
        ['"'] = "&quot;",
        ["'"] = "&#39;",
        ["/"] = "&#47;"
    }))
end -- https://github.com/kernelsauce/turbo/blob/master/turbo/escape.lua

--[[
freechains://?cmd=publish&cfg=/data/ceu/ceu-libuv/ceu-libuv-freechains/cfg/config-8400.lua
freechains::-1?cmd=publish&cfg=/data/ceu/ceu-libuv/ceu-libuv-freechains/cfg/config-8400.lua

freechains://<address>:<port>/<chain>/<work>/<hash>?

]]

local address, port, res = string.match(url, 'freechains://([^:]*):([^/]*)(/.*)')
--print(address , port , res)
ASR(address and port and res)
log:write('URL: '..res..'\n')

DAEMON = {
    address = address,
    port    = ASR(tonumber(port)),
}
daemon = DAEMON.address..':'..DAEMON.port
local c = assert(socket.connect(DAEMON.address,DAEMON.port))

-- new
if not cmd then
    cmd = string.match(res, '^/%?cmd=(new)')
end

-- subscribe
if not cmd then
    chain, cmd = string.match(res, '^(/[^/]*)/%?cmd=(subscribe)')
end
if not cmd then
    chain, cmd, address, port = string.match(res, '^(/[^/]*)/%?cmd=(subscribe)&peer=(.*):(.*)')
end

-- publish
if not cmd then
    chain, cmd = string.match(res, '^(/[^/]*)/%?cmd=(publish)')
end

-- atom
if not cmd then
    chain, cmd = string.match(res, '^(/.*)/%?cmd=(atom)')
end

log:write('INFO: .'..cmd..'.\n')

if cmd=='new' or cmd=='subscribe' then
    -- get chain
    if cmd == 'new' then
        local f = io.popen('zenity --entry --title="Join new chain" --text="Chain path:"')
        chain = f:read('*a')
        chain = string.sub(chain,1,-2)
        local ok = f:close()
        if not ok then
            log:write('ERR: '..chain..'\n')
            goto END
        end
    end

    -- subscribe
    c:send("FC chain create\n"..chain.."\n")

elseif cmd == 'publish' then
    local f = io.popen('zenity --text-info --editable --title="Publish to '..chain..'"')
    local payload = f:read('*a')
    local ok = f:close()
    if not ok then
        log:write('ERR: '..payload..'\n')
        goto END
    end

    c:send("FC chain put\n"..chain.."\nutf8\nnow\nfalse\n"..payload.."\n\n")

--[=[
elseif cmd == 'removal' then
    error'TODO'
    FC.send(0x0300, {
        chain = {
            key   = key,
            zeros = assert(tonumber(zeros)),
        },
        removal = block,
    }, DAEMON)
]=]

elseif cmd == 'atom' then
    TEMPLATES =
    {
        feed = [[
            <feed xmlns="http://www.w3.org/2005/Atom">
                <title>__TITLE__</title>
                <updated>__UPDATED__</updated>
                <id>
                    freechains:__CHAIN__/
                </id>
            __ENTRIES__
            </feed>
        ]],
        entry = [[
            <entry>
                <title>__TITLE__</title>
                <id>
                    freechains:__CHAIN__/__HASH__/
                </id>
                <published>__DATE__</published>
                <content type="html">__PAYLOAD__</content>
            </entry>
        ]],
    }

    -- TODO: hacky, "plain" gsub
    gsub = function (a,b,c)
        return string.gsub(a, b, function() return c end)
    end

    CFG   = {}
    -- TODO: check if chain exists // chain = ...
    if not chain then
        entries = {}
        entry = TEMPLATES.entry
        entry = gsub(entry, '__TITLE__',   'not subscribed')
        entry = gsub(entry, '__CHAIN__',   chain)
        entry = gsub(entry, '__HASH__',    string.rep('00', 32))
        entry = gsub(entry, '__DATE__',    os.date('!%Y-%m-%dT%H:%M:%SZ', os.time()))
        entry = gsub(entry, '__PAYLOAD__', 'not subscribed')
        entries[#entries+1] = entry
    else
        entries = {}

        CFG.external = CFG.external or {}
        CFG.external.liferea = CFG.external.liferea or {}
        T = CFG.external.liferea

        --for i=CHAIN.zeros, 255 do
for i=1,1 do
            T[chain] = T[chain] or 0
            --for node in FC.get_iter({key=CHAIN.key,zeros=i}, T[CHAIN], DAEMON) do
	    for i=1,0 do
                T[chain] = (node.seq>T[chain] and node.seq) or T[chain]
                if node.pub then
                    payload = node.pub.payload --or ('Removed publication: '..node.pub.removal))
                    title = FC.escape(string.match(payload,'([^\n]*)'))

                    payload = payload .. [[


-------------------------------------------------------------------------------

<!--
- [X](freechains:/]]..chain..'/'..i..'/'..node.pub.hash..[[/?cmd=republish)
Republish Contents
- [X](freechains:/]]..chain..'/'..i..'/'..node.hash..[[/?cmd=removal)
Inappropriate Contents
-->
]]

                    -- freechains links
                    payload = string.gsub(payload, '(%[.-%]%(freechains:)(/.-%))', '%1//'..daemon..'%2')

                    -- markdown
--if false then
                    do
                        local tmp = os.tmpname()
                        local md = assert(io.popen('pandoc -r markdown -w html > '..tmp, 'w'))
                        md:write(payload)
                        assert(md:close())
                        local html = assert(io.open(tmp))
                        payload = html:read('*a')
                        html:close()
                        os.remove(tmp)
                    end
--end

                    payload = FC.escape(payload)

                    entry = TEMPLATES.entry
                    entry = gsub(entry, '__TITLE__',   title)
                    entry = gsub(entry, '__CHAIN__',   chain)
                    entry = gsub(entry, '__HASH__',    node.hash)
                    entry = gsub(entry, '__DATE__',    os.date('!%Y-%m-%dT%H:%M:%SZ', node.pub.timestamp/1000000))
                    entry = gsub(entry, '__PAYLOAD__', payload)
                    entries[#entries+1] = entry
                end
            end

            -- avoids polluting CFG if only genesis so far
            if T[chain] > 0 then
                CFG.external.liferea[chain] = nil
            end
        end

        -- MENU
        do
            entry = TEMPLATES.entry
            entry = gsub(entry, '__TITLE__',   'Menu')
            entry = gsub(entry, '__CHAIN__',   chain)
            entry = gsub(entry, '__HASH__',    FC.hash2hex(string.rep('\0',32)))
            entry = gsub(entry, '__DATE__',    os.date('!%Y-%m-%dT%H:%M:%SZ', 25000))
            entry = gsub(entry, '__PAYLOAD__', FC.escape([[
<ul>
]]..(chain~='/' and '' or [[
<li> <a href="freechains://]]..daemon..[[/?cmd=new">[X]</a> join new chain
]])..[[
<li> <a href="freechains://]]..daemon..chain..[[/?cmd=publish">[X]</a> publish to "]]..chain..[["
</ul>
]]))
            entries[#entries+1] = entry
        end
    end

    feed = TEMPLATES.feed
    feed = gsub(feed, '__TITLE__',   chain)
    feed = gsub(feed, '__UPDATED__', os.date('!%Y-%m-%dT%H:%M:%SZ', os.time()))
    feed = gsub(feed, '__CHAIN__',   chain)
    feed = gsub(feed, '__ENTRIES__', table.concat(entries,'\n'))

    f = io.stdout --assert(io.open(dir..'/'..key..'.xml', 'w'))
    f:write(feed)

    -- configure: save last.atom
    --FC.send(0x0500, CFG, DAEMON)

    goto END

end

::OK::
os.execute('zenity --info --text="OK"')
goto END

::ERROR::
os.execute('zenity --error')

::END::

log:close()
