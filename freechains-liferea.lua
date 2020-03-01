#!/usr/bin/env lua5.3

-- xhost +

local socket = require 'socket'
local json   = require 'json'

local PATH_CFG   = os.getenv('HOME')..'/.config/freechains-liferea.json'
local PATH_SHARE = os.getenv('HOME')..'/.local/share/freechains-liferea/'
local PATH_DATA  = PATH_SHARE..'data/'
local PATH_LOG   = PATH_SHARE..'log.txt'
os.execute('mkdir -p '..PATH_SHARE)

local LOG = assert(io.open(PATH_LOG,'a+'))
--local LOG = io.stderr

local CFG = {
    first   = true,
    path    = PATH_DATA,
    chains  = {},
    friends = {},
}

function CFG_ (cmd)
    if cmd == 'load' then
        local f = io.open(PATH_CFG)
        if f then
            CFG = json.decode(f:read('*a'))
            f:close()
        end
    else
        local f = assert(io.open(PATH_CFG,'w'))
        f:write(json.encode(CFG)..'\n')
        f:close()
    end
end

function CFG_chain (chain)
    local t = CFG.chains[chain] or { peers={} }
    CFG.chains[chain] = t
    CFG_('save')
    return t
end

function MINE (chain)
    return (chain == '/'..CFG.nick)
end

CFG_('load')

-------------------------------------------------------------------------------

function EXE (cmd)
    --LOG:write('EXE: '..cmd..'\n')
    local f = io.popen(cmd)
    local ret = f:read("*a")
    local ok = f:close()
    --LOG:write('>>> ret='..tostring(ret)..'\n')
    if ok and string.sub(ret,-1,-1)=='\n' then
        ret = string.sub(ret,1,-2)  -- except "--text-info" enters here
    end
    return ok and ret
end

function EXE_BG (cmd)
    io.popen(cmd)
end

function EXE_FC (cmd,opts)
    opts = opts or ''
    return EXE('freechains --host=localhost:'..CFG.port..' '..opts..' '..string.sub(cmd,12))
end

-------------------------------------------------------------------------------

local CMD = (...)
LOG:write('CMD: '..tostring(CMD)..'\n')

if CMD == nil then
    if CFG.first then
        CFG.first = false

        local z = (
            'zenity --forms --title="Welcome to Freechains!"'   ..
            '   --separator="\t"'                               ..
            '   --add-entry="Nickname:"'                        ..
            '   --add-password="Password:"'                     ..
            '   --add-entry="Port:"'                            ..
            ''
        )
        local ret = EXE(z)
        if not ret then
            LOG:write('ERR: '..CMD..'\n')
            goto END
        end
        local nick,pass,port = string.match(ret, '^(.*)\t(.*)\t(.*)$')
        assert(not string.find(nick,'%W'), 'nickname should only contain alphanumeric characters')

        CFG.nick = nick
        CFG.port = (port ~= '') and port or '8330'

        EXE('freechains host create '..CFG.path..' '..CFG.port)
        EXE_BG('freechains host start '..CFG.path)
        EXE('sleep 0.5')

        local ret = EXE_FC('freechains crypto create pubpvt '..pass)
        local pub,pvt = string.match(ret, '^([^\n]*)\n(.*)$')
        CFG.keys = { pub=pub, pvt=pvt }
        CFG.friends[pub] = nick

        local chain = '/'..nick

        CFG_('save')

        EXE_FC('freechains chain join '..chain..' pubpvt '..pub..' '..pvt)
        EXE_BG('liferea')
        EXE('dbus-send --session --dest=org.gnome.feed.Reader --type=method_call /org/gnome/feed/Reader org.gnome.feed.Reader.Subscribe "string:|freechains-liferea freechains://chain-atom-'..chain..'"')
    else
        EXE_BG('freechains host start '..CFG.path)
        EXE_BG('liferea')
    end
    os.exit(0)
end

if CMD == 'stop' then
    EXE('killall liferea')
    EXE_FC('freechains host stop')
    os.exit(0)
end

-------------------------------------------------------------------------------

if string.sub(CMD,1,13) ~= 'freechains://' then
    os.execute('xdg-open '..CMD)
    os.exit(0)
end

function assert (cnd, msg)
    msg = msg or 'malformed command'
    if not cnd then
        LOG:write('ERROR: '..msg..'\n')
        os.exit(1)
    end
    return cnd
end

-------------------------------------------------------------------------------

CMD = string.match(CMD, 'freechains://(.*)')
CMD = 'freechains '..string.gsub(CMD, '-', ' ')

-------------------------------------------------------------------------------

function hash2hex (hash)
    local ret = ''
    for i=1, string.len(hash) do
        ret = ret .. string.format('%02X', string.byte(string.sub(hash,i,i)))
    end
    return ret
end

function escape (html)
    return (string.gsub(html, "[}{\">/<'&]", {
        ["&"] = "&amp;",
        ["<"] = "&lt;",
        [">"] = "&gt;",
        ['"'] = "&quot;",
        ["'"] = "&#39;",
        ["/"] = "&#47;"
    }))
end -- https://github.com/kernelsauce/turbo/blob/master/turbo/escape.lua

function iter (chain)
    local visited = {}
    local heads   = {}

    local function one (hash,init)
        if visited[hash] then return end
        visited[hash] = true

        LOG:write('freechains chain get '..chain..' '..hash..'\n')
        local ret = EXE_FC('freechains chain get '..chain..' '..hash)

        local block = json.decode(ret)
        if not init then
            coroutine.yield(block)
        end

        for _, front in ipairs(block.fronts) do
            one(front)
        end

        if #block.fronts == 0 then
            heads[#heads+1] = hash
        end
    end

    return coroutine.wrap(
        function ()
            local cfg = CFG_chain(chain)
            if cfg.heads then
                for _,hash in ipairs(cfg.heads) do
                    one(hash,true)
                end
            else
                local hash = EXE_FC('freechains chain genesis '..chain)
                one(hash,true)
            end

            cfg.heads = heads
            CFG_('save')
        end
    )
end

-------------------------------------------------------------------------------

if CMD == 'freechains chain join' then

    --local z = EXE('zenity --entry --title="Join new chain" --text="Chain path:"')
    local z = (
        'zenity --forms --title="Join new chain"' ..
        '   --separator="\t"'          ..
        '   --add-entry="Chain path:"' ..
        '   --add-entry="First peer:"' ..
        ''
    )

    local ret = EXE(z)
    if not ret then
        LOG:write('ERR: '..CMD..'\n')
        goto END
    end
    local chain,peer = string.match(ret, '^(.*)\t(.*)$')

    if (peer ~= '') then
        local t = CFG_chain(chain).peers
        t[peer] = true
        CFG_('save')
    end

    EXE_FC(CMD..' '..chain)
    EXE('dbus-send --session --dest=org.gnome.feed.Reader --type=method_call /org/gnome/feed/Reader org.gnome.feed.Reader.Subscribe "string:|freechains-liferea freechains://chain-atom-'..chain..'"')

elseif string.sub(CMD,1,21) == 'freechains chain post' then

    local chain = string.match(CMD, ' ([^ ]*)$')
    local pay = EXE('zenity --text-info --editable --title="Publish to '..chain..'"')
    if not pay then
        LOG:write('ERR: '..CMD..'\n')
        goto END
    end

    local file = os.tmpname()..'.pay'
    local f = assert(io.open(file,'w')):write(pay..'\nEOF\n')
    f:close()
    EXE_FC(CMD..' file utf8 '..file, '--utf8-eof=EOF --sign='..CFG.keys.pvt)

elseif string.sub(CMD,1,21) == 'freechains chain atom' then

    local chain = string.match(CMD, ' ([^ ]*)$')

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

    local entries = {}

    for block in iter(chain) do
        local payload = block.hashable.payload
        local title = escape(string.match(payload,'([^\n]*)'))
        local signed = block.signature==json.util.null and 'Not signed' or
            'Signed by '..(CFG.friends[block.signature.pub] or '@'..string.sub(block.signature.pub,1,9))

        payload = payload .. [[


-------------------------------------------------------------------------------

]]..signed..[[

<!--
- [X](liferea:/]]..chain..'/'..block.hash..[[/?cmd=republish)
Republish Contents
- [X](liferea:/]]..chain..'/'..block.hash..[[/?cmd=removal)
Inappropriate Contents
-->
]]

        -- markdown
if true then
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
end

        payload = escape(payload)

        entry = TEMPLATES.entry
        entry = gsub(entry, '__TITLE__',   title)
        entry = gsub(entry, '__CHAIN__',   chain)
        entry = gsub(entry, '__HASH__',    block.hash)
        entry = gsub(entry, '__DATE__',    os.date('!%Y-%m-%dT%H:%M:%SZ', block.hashable.timestamp))
        entry = gsub(entry, '__PAYLOAD__', payload)
        entries[#entries+1] = entry
    end

    -- MENU
    do
        entry = TEMPLATES.entry
        entry = gsub(entry, '__TITLE__',   'Menu')
        entry = gsub(entry, '__CHAIN__',   chain)
        entry = gsub(entry, '__HASH__',    hash2hex(string.rep('\0',32)))
        entry = gsub(entry, '__DATE__',    os.date('!%Y-%m-%dT%H:%M:%SZ', 25000))
        entry = gsub(entry, '__PAYLOAD__', escape([[
<ul>
]]..(not MINE(chain) and '' or [[
<li> <a href="freechains://chain-join">[X]</a> join new chain
]])..[[
<li> <a href="freechains://chain-post-]]..chain..[[">[X]</a> post to "]]..chain..[["
</ul>
]]))
        entries[#entries+1] = entry
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
--os.execute('zenity --info --text="OK"')
goto END

::ERROR::
os.execute('zenity --error')

::END::

LOG:close()
