-- [scripts/WitheringBrews/Debug.lua]
WitheringBrews       = WitheringBrews or {}
WitheringBrews.Debug = WitheringBrews.Debug or {}

local WB             = WitheringBrews
local D              = WitheringBrews.Debug

local function out(prefix, msg)
    if WB.Logger and WB.Logger.Warn then
        WB.Logger:Warn(prefix .. msg)
    else
        System.LogAlways("[WitheringBrews] " .. prefix .. msg)
    end
end

function D.info(msg) out("", msg) end

function D.warn(msg) out("[WARN] ", msg) end

function D.error(msg) out("[ERROR] ", msg) end

function D.printf(fmt, ...)
    D.info(string.format(fmt, ...))
end
