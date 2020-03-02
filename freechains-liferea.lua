#!/usr/bin/env lua5.3

--local PATH_SHARE = os.getenv('HOME')..'/.local/share/freechains/'
--PATH_LOG = PATH_SHARE..'log.txt'
--local LOG = assert(io.open(PATH_LOG,'a+'))
--local LOG = io.stderr
--LOG:write('CMD: '..tostring(CMD)..'\n')

local cmd = (...)

-------------------------------------------------------------------------------

if string.sub(cmd,1,13) ~= 'freechains://' then
    os.execute('xdg-open '..cmd)
    os.exit(0)

else
    cmd = string.gsub(string.sub(cmd,14), '-', ' ')
    os.execute('freechains-ui '..cmd)

end

--LOG:close()
