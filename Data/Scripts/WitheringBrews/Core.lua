WitheringBrews = WitheringBrews or {}
local WB       = WitheringBrews

WB.Config      = WB.Config or { Version = "0.0.1-dev" }
WB._registered = WB._registered or false
WB._ready      = WB._ready or false

local function LOG(m)
    if WB.Logger and WB.Logger.Warn then WB.Logger:Warn(m) else System.LogAlways("[WitheringBrews] " .. m) end
end

local function ensureDB()
    if not WB.DB and KCDUtils and KCDUtils.DB and KCDUtils.DB.Factory then
        WB.DB = KCDUtils.DB.Factory("witheringbrews")
    end
    return WB.DB
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
            -- Replay once in case gameplay already started:
            WB:OnGameplayStarted()
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

function WB:OnGameplayStarted()
    if WB._ready then return end
    if not WB._registered and KCDUtils and KCDUtils.RegisterMod then
        local mod = KCDUtils.RegisterMod({ Name = "witheringbrews" })
        WB.Logger = mod.Logger
        WB._registered = true
        ensureDB()
    end
    WB._ready = true
    LOG(("OnGameplayStarted → ready (v%s)"):format(self.Config.Version or "?"))

    -- DB smoke
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

-- Public stubs (real logic later)
function WB.RegisterNewStacks(ctx) LOG("RegisterNewStacks (stub)") end

function WB.AgeAndDowngrade() LOG("AgeAndDowngrade (stub)") end

function WB.Tick(ctx)
    WB.RegisterNewStacks(ctx); WB.AgeAndDowngrade()
end

-- CCommand fallbacks (always available)
function WitheringBrews_Cmd_Ping() LOG("ping OK (CCommand)") end

-- --- Event handlers (log-only baseline) ---
function WB:OnHide(...) LOG("OnHide (fade) args=" .. select("#", ...)) end

function WB:OnShow(...) LOG("OnShow (fade) args=" .. select("#", ...)) end

function WB:OnInventoryOpened(...) LOG("Inventory opened args=" .. select("#", ...)) end

function WB:OnInventoryClosed(...) LOG("Inventory closed args=" .. select("#", ...)) end

-- ---- Inventory FSCommand probes ----

-- Inventory probes
local function dumpArgs(tag, ...)
    local n = select("#", ...); local t = {}; for i = 1, n do t[i] = tostring(select(i, ...)) end; System.LogAlways(("[WitheringBrews] %s args[%d]=%s")
        :format(tag, n, table.concat(t, ", ")))
end

-- Inventory probes
local function dumpArgs(tag, ...)
    local n = select("#", ...); local t = {}; for i = 1, n do t[i] = tostring(select(i, ...)) end; System.LogAlways(("[WitheringBrews] %s args[%d]=%s")
        :format(tag, n, table.concat(t, ", ")))
end
function WB:OnItemTransferOpened(...)
    if WB.Logger then
        WB.Logger:Warn("ItemTransfer opened (EL)")
    else
        System.LogAlways(
            "[WitheringBrews] ItemTransfer opened (EL)")
    end
end

function WB:OnItemTransferClosed(...)
    if WB.Logger then
        WB.Logger:Warn(
            "ItemTransfer closed (EL) → (next) delta & cohorts")
    else
        System.LogAlways(
            "[WitheringBrews] ItemTransfer closed (EL)")
    end
end

local function dumpArgs(tag, ...)
    local n = select("#", ...); local t = {}; for i = 1, n do t[i] = tostring(select(i, ...)) end; System.LogAlways(("[WitheringBrews] %s args[%d]=%s")
        :format(tag, n, table.concat(t, ", ")))
end
function WB:OnInventory_General(...) dumpArgs("ApseInventoryList.OnGeneralEvent", ...) end

function WB:OnInventory_StartDrag(...) dumpArgs("ApseInventoryList.OnStartDrag", ...) end

function WB:OnInventory_DropArea(...) dumpArgs("ApseInventoryList.OnDropActiveAreaChanged", ...) end

function WB:OnInventory_FocusTab(...) dumpArgs("ApseInventoryList.OnFocusTab", ...) end

function WB:OnInventory_DoubleClicked(...) dumpArgs("ApseInventoryList.OnDoubleClicked", ...) end

function WitheringBrews_Cmd_DbTest()
    local db = ensureDB()
    if not db then
        System.LogAlways("[WitheringBrews] DB missing"); return
    end
    db:Set("WB_Config:ccmd", { t = os.time(), note = "from CCmd" })
    System.LogAlways("[WitheringBrews] db_test set->get: " .. (db:Get("WB_Config:ccmd") and "OK" or "nil"))
    db:Del("WB_Config:ccmd")
    System.LogAlways("[WitheringBrews] db_test del: " .. (db:Get("WB_Config:ccmd") == nil and "OK" or "FAILED"))
end

-- [scripts/WitheringBrews/Core.lua] (CCommands)
function WitheringBrews_Cmd_DbPut(key, value)
    local WB = WitheringBrews
    if not key then
        System.LogAlways("[WitheringBrews] usage: wb_db_put <key> <value>"); return
    end
    local db = WB.DB or (KCDUtils and KCDUtils.DB and KCDUtils.DB.Factory and KCDUtils.DB.Factory("witheringbrews"))
    if not db then
        System.LogAlways("[WitheringBrews] DB missing"); return
    end
    db:Set(key, value or "1")
    System.LogAlways("[WitheringBrews] db_put " .. key .. "=" .. tostring(value or "1"))
end

function WitheringBrews_Cmd_DbGet(key)
    local WB = WitheringBrews
    if not key then
        System.LogAlways("[WitheringBrews] usage: wb_db_get <key>"); return
    end
    local db = WB.DB or (KCDUtils and KCDUtils.DB and KCDUtils.DB.Factory and KCDUtils.DB.Factory("witheringbrews"))
    if not db then
        System.LogAlways("[WitheringBrews] DB missing"); return
    end
    local v = db:Get(key)
    System.LogAlways("[WitheringBrews] db_get " .. key .. " -> " .. tostring(v))
end

function WitheringBrews_Cmd_UiDiag()
    local f = function(x) return (UIAction and UIAction[x]) and "yes" or "no" end
    System.LogAlways("[WitheringBrews] UIAction? " .. (UIAction and "yes" or "no"))
    System.LogAlways("[WitheringBrews]  - RegisterEventSystemListener: " .. f("RegisterEventSystemListener"))
    System.LogAlways("[WitheringBrews]  - RegisterEventMovieListener: " .. f("RegisterEventMovieListener"))
    System.LogAlways("[WitheringBrews]  - RegisterFSCommandListener: " .. f("RegisterFSCommandListener"))
end
