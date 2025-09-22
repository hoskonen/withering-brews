-- [scripts/WitheringBrews/Core.lua]
WitheringBrews = WitheringBrews or {}
local WB = WitheringBrews

WB.Config = WB.Config or { Version = "0.0.1-dev" }
WB._registered = WB._registered or false
WB._ready = WB._ready or false
WB._sawGameplayStart = WB._sawGameplayStart or false

-- Attach logger/DB without replacing WB table
local function AttachKCD(mod)
    WB.Logger      = mod.Logger
    WB.DB          = mod.DB
    WB._registered = true
    if WB.Logger and WB.Logger.Warn then
        WB.Logger:Warn(("WitheringBrews registered v%s"):format(WB.Config.Version))
    else
        System.LogAlways("[WitheringBrews] registered (no logger interface?)")
    end
    -- Subscribe to KCDUtils bus for future starts
    if KCDUtils and KCDUtils.Events and KCDUtils.Events.Subscribe then
        KCDUtils.Events.Subscribe("OnGameplayStarted", function()
            WB:OnGameplayStarted()
        end)
    end
    -- If gameplay already started earlier, replay now
    if WB._sawGameplayStart then
        WB:OnGameplayStarted()
    end
end

-- Try to register now; if KU not ready, we’ll retry later
function WB.EnsureRegistered()
    if WB._registered then return true end
    if _G.KCDUtils and KCDUtils.RegisterMod then
        local mod = KCDUtils.RegisterMod({ Name = "witheringbrews" })
        AttachKCD(mod)
        return true
    end
    return false
end

-- One-shot delayed handshake for startup race (call this from init once)
function WB.Handshake(maxTries, delayMs)
    if WB._registered then return end
    maxTries    = maxTries or 50 -- ~5s
    delayMs     = delayMs or 100
    local tries = 0
    local function tick()
        if WB.EnsureRegistered() then return end
        tries = tries + 1
        if tries < maxTries then
            Script.SetTimer(delayMs, tick)
        else
            System.LogAlways("[WitheringBrews] KCDUtils never appeared (handshake exhausted)")
        end
    end
    Script.SetTimer(delayMs, tick)
end

-- Your gameplay-ready hook (idempotent)
function WB:OnGameplayStarted()
    self._sawGameplayStart = true
    if not self._registered then
        -- Don’t print “no logger”; just ensure register & replay
        self.EnsureRegistered()
    end
    if self._ready then return end
    self._ready = true

    local ver = (self.Config and self.Config.Version) or "?"
    if self.Logger and self.Logger.Warn then
        self.Logger:Warn(("OnGameplayStarted → Withering Brews ready (v%s)"):format(ver))
    else
        System.LogAlways("[WitheringBrews] ready (logger not attached yet)")
    end
end
