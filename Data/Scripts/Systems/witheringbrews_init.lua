-- [scripts/WitheringBrews/init.lua]
Script.ReloadScript("scripts/WitheringBrews/Config.lua")
Script.ReloadScript("scripts/WitheringBrews/Core.lua")

local C = WitheringBrews and WitheringBrews.Config or { Name = "WitheringBrews", Version = "?" }
System.LogAlways(("[%s] loaded (init.lua) v%s"):format(C.Name, C.Version))

-- Idempotent boot guard
if not WitheringBrews._booted then
    WitheringBrews._booted = true
    WitheringBrews.Boot()
else
    System.LogAlways(("[%s] already booted; skipping Boot()"):format(C.Name))
end

-- Simple console ping for manual check
System.AddCCommand("wb_ping", "WitheringBrews_Ping()", "Withering Brews: log a ping")
function WitheringBrews_Ping()
    local CC = WitheringBrews.Config or C
    System.LogAlways(("[%s] wb_ping OK (v%s)"):format(CC.Name, CC.Version))
end
