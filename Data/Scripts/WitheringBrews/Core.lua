-- [scripts/WitheringBrews/Core.lua]
WitheringBrews = WitheringBrews or {}
WitheringBrews.Config = WitheringBrews.Config or { Version = "0.0.1-dev" }

local function registerWithKCDUtils(tag)
    if _G.KCDUtils and KCDUtils.RegisterMod and not WitheringBrews._registered then
        local mod                  = KCDUtils.RegisterMod({ Name = "witheringbrews" })
        -- attach instead of replacing, so our methods survive
        WitheringBrews.Logger      = mod.Logger
        WitheringBrews.DB          = mod.DB
        WitheringBrews._registered = true
        (WitheringBrews.Logger or System).LogAlways(
            ("[witheringbrews] registered v%s (%s)")
            :format((WitheringBrews.Config and WitheringBrews.Config.Version) or "?", tag or "ogs"))
        -- optional: subscribe to KCDUtils bus going forward
        if KCDUtils.Events and KCDUtils.Events.Subscribe then
            KCDUtils.Events.Subscribe("OnGameplayStarted", function()
                -- proves bus subscription works next time
                if WitheringBrews.Logger then
                    WitheringBrews.Logger:Warn("KCDUtils.Events → OnGameplayStarted received")
                end
            end)
        end
        return true
    end
    return false
end

-- This is the method called by UIAction.RegisterEventSystemListener
function WitheringBrews:OnGameplayStarted()
    -- If we don't have a logger yet, register NOW (KCDUtils is up at this point)
    if not self.Logger then
        local ok = registerWithKCDUtils("OnGameplayStarted")
        if not ok then
            -- extremely early edge case; still print something
            System.LogAlways("[WitheringBrews] OnGameplayStarted (logger still not ready)")
            return
        end
    end
    -- Now we have a logger → loud, verified line:
    self.Logger:Warn(("OnGameplayStarted → Withering Brews ready (v%s)")
        :format((self.Config and self.Config.Version) or "?"))
end
