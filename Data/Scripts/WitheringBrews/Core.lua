-- [scripts/WitheringBrews/Core.lua]
WitheringBrews = WitheringBrews or {}
local WB       = WitheringBrews

WB.Config      = WB.Config or { Version = "0.0.1-dev" }
WB._registered = WB._registered or false
WB._ready      = WB._ready or false

local function LOG(m) if WB.Logger and WB.Logger.Warn then WB.Logger:Warn(m) else System.LogAlways("[WitheringBrews] " ..
        m) end end

local function ensureDB()
    if not WB.DB and KCDUtils and KCDUtils.DB and KCDUtils.DB.Factory then
        WB.DB = KCDUtils.DB.Factory("witheringbrews")
    end
    return WB.DB
end

-- Replay guard so we don’t double-init
WB._bootReplayed = WB._bootReplayed or false

local function replayOnceAfterAttach()
    if WB._bootReplayed then return end
    WB._bootReplayed = true
    -- Call our handler once so DB smoke runs even if we missed the event
    WB:OnGameplayStarted()
end

function WB.Handshake(maxTries, delayMs)
    if WB._registered then return end
    maxTries, delayMs = maxTries or 50, delayMs or 100
    local tries = 0
    local function tick()
        if not WB._registered and KCDUtils and KCDUtils.RegisterMod then
            local mod = KCDUtils.RegisterMod({ Name = "witheringbrews" })
            WB.Logger = mod.Logger
            WB._registered = true
            ensureDB(); LOG(("WitheringBrews registered v%s"):format(WB.Config.Version))
            replayOnceAfterAttach() -- <-- force one init pass now
            return
        end
        tries = tries + 1
        if tries < maxTries then
            Script.SetTimer(delayMs, tick)
        else
            System.LogAlways("[WitheringBrews] KCDUtils did not appear")
        end
    end
    Script.SetTimer(delayMs, tick)
end

-- Your lifecycle; keeps DB smoke so we see it in logs
function WB:OnGameplayStarted()
    if not WB._registered then
        -- try to attach right now if possible, otherwise we’ll run smoke later via replay
        if KCDUtils and KCDUtils.RegisterMod then
            local mod = KCDUtils.RegisterMod({ Name = "witheringbrews" })
            WB.Logger = mod.Logger
            WB._registered = true
            ensureDB()
        end
    end
    if WB._ready then return end
    WB._ready = true

    LOG(("OnGameplayStarted → ready (v%s)"):format(self.Config.Version or "?"))

    local db = ensureDB()
    if db then
        db:Set("WB_Config:ping", { t = os.time(), note = "hello-db" })
        LOG("DB smoke: read " .. (db:Get("WB_Config:ping") and "OK" or "nil"))
        db:Del("WB_Config:ping")
        LOG("DB smoke: delete " .. (db:Get("WB_Config:ping") == nil and "OK" or "FAILED"))
    else
        LOG("DB smoke: DB not attached yet")
    end
end

-- Probes for other events (so you see signals)
function WB:OnHide() LOG("OnHide (fade)") end

function WB:OnShow() LOG("OnShow (fade)") end

function WB:OnItemTransferOpened() LOG("ItemTransfer opened") end

function WB:OnItemTransferClosed() LOG("ItemTransfer closed") end

function WB:OnInventoryOpened() LOG("Inventory opened") end

function WB:OnInventoryClosed() LOG("Inventory closed") end
