-- [scripts/WitheringBrews/Core.lua]
WitheringBrews = WitheringBrews or {}

function WitheringBrews.Boot()
    local C = WitheringBrews.Config or { Name = "WitheringBrews", Version = "?" }
    System.LogAlways(("[%s] Core.Boot v%s"):format(C.Name, C.Version))

    -- Post-boot sanity ping (fires shortly after init)
    Script.SetTimer(250, function()
        System.LogAlways(("[%s] Post-boot ping OK"):format(C.Name))
    end)
end
