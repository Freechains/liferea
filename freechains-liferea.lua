#!/usr/bin/env lua5.3

local socket = require 'socket'
local json   = require 'json'

-------------------------------------------------------------------------------

local CFG = {
    chains = {}
}
do
    local f = io.open(os.getenv('HOME')..'/.config/freechains-liferea.json')
    if f then
        CFG = json.decode(f:read('*a'))
        f:close()
    end
end

local CMD = assert((...))

local LOG = assert(io.open('/tmp/log.txt','a+'))
--local LOG = io.stderr
LOG:write('CMD: '..CMD..'\n')

if string.sub(CMD,1,13) ~= 'freechains://' then
    os.execute('xdg-open '..CMD)
    os.exit(0)
end

CMD = string.match(CMD, 'freechains://(.*)')
CMD = 'freechains '..string.gsub(CMD, '-', ' ')

-------------------------------------------------------------------------------

function exe (cmd)
    LOG:write(cmd..'\n')
    local f = io.popen(cmd)
    local ret = f:read("*a")
    local ok = f:close()
    return ok and ret
end

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

        local ret = exe('freechains chain get '..chain..' '..hash)

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
            local cfg = CFG.chains[chain] or {}
            CFG.chains[chain] = cfg
            if cfg.heads then
                for _,hash in ipairs(cfg.heads) do
                    one(hash,true)
                end
            else
                local hash = exe('freechains chain genesis '..chain)
                one(hash,true)
            end

            cfg.heads = heads
            local f = assert(io.open(os.getenv('HOME')..'/.config/freechains-liferea.json','w'))
            f:write(json.encode(CFG)..'\n')
            f:close()
        end
    )
end

-------------------------------------------------------------------------------

if CMD == 'freechains chain join' then

    local chain = exe('zenity --entry --title="Join new chain" --text="Chain path:"')
    if not chain then
        LOG:write('ERR: '..CMD..'\n')
        goto END
    end
    chain = string.sub(chain,1,-2)
    exe(CMD..' '..chain)
    exe('dbus-send --session --dest=org.gnome.feed.Reader --type=method_call /org/gnome/feed/Reader org.gnome.feed.Reader.Subscribe "string:|freechains-liferea freechains://chain-atom-'..chain..'"')

elseif string.sub(CMD,1,21) == 'freechains chain post' then

    local chain = string.match(CMD, ' ([^ ]*)$')
    local pay = exe('zenity --text-info --editable --title="Publish to '..chain..'"')
    if not pay then
        LOG:write('ERR: '..CMD..'\n')
        goto END
    end

    local file = os.tmpname()..'.pay'
    local f = assert(io.open(file,'w')):write(pay..'\nEOF\n')
    f:close()
    exe(CMD..' file utf8 '..file..' --utf8-eof=EOF')

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

        payload = payload .. [[


-------------------------------------------------------------------------------

<!--
- [X](liferea:/]]..chain..'/'..block.hash..[[/?cmd=republish)
Republish Contents
- [X](liferea:/]]..chain..'/'..block.hash..[[/?cmd=removal)
Inappropriate Contents
-->
]]

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
]]..(chain~='/' and '' or [[
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
