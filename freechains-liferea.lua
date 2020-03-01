#!/usr/bin/env lua5.3

local PATH_SHARE = os.getenv('HOME')..'/.local/share/freechains/'
PATH_LOG = PATH_SHARE..'log.txt'
local LOG = assert(io.open(PATH_LOG,'a+'))
--local LOG = io.stderr

function CFG_chain (chain)
    local t = CFG.chains[chain] or { peers={} }
    CFG.chains[chain] = t
    CFG_('save')
    return t
end

function CFG_peers (chain)
    local ps = {}
    for p in pairs(CFG_chain(chain).peers) do
        ps[#ps+1] = p
    end
    return ps
end

function MINE (chain)
    return (chain == '/'..CFG.keys.pub)
end

function NICK (chain)
    local pub  = string.sub(chain,2)
    local nick = CFG.friends[pub]
    return (nick and '/'..nick) or chain
end

-------------------------------------------------------------------------------

local CMD = (...)
LOG:write('CMD: '..tostring(CMD)..'\n')

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

if string.sub(CMD,1,15) == 'freechains nick' then

    local pub = string.match(CMD, ' ([^ ]*)$')
    local z = EXE('zenity --entry --title="Add nickname for" '..pub..' --text="Nickname:"')
    local nick = EXE(z)
    if not nick then goto END end

    CFG.friends[pub] = nick
    CFG_('save')

    EXE_FC('freechains chain join /'..pub..' '..pub)
    EXE('dbus-send --session --dest=org.gnome.feed.Reader --type=method_call /org/gnome/feed/Reader org.gnome.feed.Reader.Subscribe "string:|freechains-liferea freechains://chain-atom-/'..pub..'"')

elseif CMD == 'freechains chain join' then

    --local z = EXE('zenity --entry --title="Join new chain" --text="Chain path:"')
    local z = (
        'zenity --forms --title="Join new chain"' ..
        '   --separator="\t"'          ..
        '   --add-entry="Chain path:"' ..
        '   --add-entry="First peer:"' ..
        ''
    )
    local ret = EXE(z)
    if not ret then goto END end

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
    if not pay then goto END end

    local file = os.tmpname()..'.pay'
    local f = assert(io.open(file,'w')):write(pay..'\nEOF\n')
    f:close()
    EXE_FC(CMD..' file utf8 '..file, '--utf8-eof=EOF --sign='..CFG.keys.pvt)

elseif string.sub(CMD,1,22) == 'freechains chain bcast' then

    local chain = string.match(CMD, ' ([^ ]*)$')
    local f = io.popen('zenity --progress --percentage=0 --title="Broadcast '..chain..'"', 'w')
    local ps = CFG_peers(chain)
    for i,p in ipairs(ps) do
        f:write('# '..p..'\n')
        --EXE('sleep 1')
        EXE_FC('freechains chain send '..chain..' '..p)
        f:write(math.floor(100*(i/#ps))..'\n')
    end
    f:close()

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
        local pub = block.signature and block.signature.pub
        local author = 'Signed by '
        do
            if block.signature == json.util.null then
                author = author .. 'Not signed'
            else
                local nick = CFG.friends[pub]
                if nick then
                    author = author .. nick
                else
                    --author = author .. '[@'..string.sub(pub,1,9)..'](freechains://nick-'..pub..')'
                    author = author .. '<a href="freechains://nick-'..pub..'">@'..string.sub(pub,1,9)..'</a>'
                end
            end
        end

        payload = payload .. [[


-------------------------------------------------------------------------------

]]..author..[[

<a href=xxx> like </a>

<a href=yyy> dislike </a>

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
        local ps = table.concat(CFG_peers(chain),',')

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
<li> <a href="freechains://chain-post-]]..chain..[[">[X]</a> post to "]]..NICK(chain)..[["
<li> <a href="freechains://chain-bcast-]]..chain..[[">[X]</a> broadcast to peers (]]..ps..[[)
</ul>
]]))
        entries[#entries+1] = entry
    end

    feed = TEMPLATES.feed
    feed = gsub(feed, '__TITLE__',   NICK(chain))
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
