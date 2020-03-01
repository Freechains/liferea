callbacks = {
    onHostCreate = function (pub)
        EXE_BG('liferea')
        EXE('sleep 1')
        EXE('dbus-send --session --dest=org.gnome.feed.Reader --type=method_call /org/gnome/feed/Reader org.gnome.feed.Reader.Subscribe "string:|freechains-liferea freechains://chain-atom-/'..pub..'"')
    end,
    onHostStart = function ()
        EXE_BG('liferea')
    end,
    onHostStop = function ()
        EXE('killall liferea')
    end,
    onChainJoin = function (chain)
        EXE('dbus-send --session --dest=org.gnome.feed.Reader --type=method_call /org/gnome/feed/Reader org.gnome.feed.Reader.Subscribe "string:|freechains-liferea freechains://chain-atom-'..chain..'"')
    end,
    onChainPost  = function (chain)
    end,
}
