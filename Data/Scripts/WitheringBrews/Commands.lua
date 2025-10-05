-- [scripts/WitheringBrews/Commands.lua]
WitheringBrews = WitheringBrews or {}
local WB, U = WitheringBrews, WitheringBrews.Util

-- --- DB helpers -------------------------------------------------------------
local function ensureDB()
    if not WB.DB and KCDUtils and KCDUtils.DB and KCDUtils.DB.Factory then
        WB.DB = KCDUtils.DB.Factory("witheringbrews")
    end
    return WB.DB
end

function WitheringBrews_Cmd_Ping()
    System.LogAlways("[WitheringBrews] ping OK (CCommand)")
end

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

function WitheringBrews_Cmd_DbPut(key, value)
    if not key then
        System.LogAlways("[WitheringBrews] usage: wb_db_put <key> <value>"); return
    end
    local db = ensureDB(); if not db then
        System.LogAlways("[WitheringBrews] DB missing"); return
    end
    db:Set(key, value or "1"); System.LogAlways("[WitheringBrews] db_put " .. key .. "=" .. tostring(value or "1"))
end

function WitheringBrews_Cmd_DbGet(key)
    if not key then
        System.LogAlways("[WitheringBrews] usage: wb_db_get <key>"); return
    end
    local db = ensureDB(); if not db then
        System.LogAlways("[WitheringBrews] DB missing"); return
    end
    local v = db:Get(key); System.LogAlways("[WitheringBrews] db_get " .. key .. " -> " .. tostring(v))
end

function WitheringBrews_Cmd_UiDiag()
    local f = function(x) return (UIAction and UIAction[x]) and "yes" or "no" end
    System.LogAlways("[WitheringBrews] UIAction? " .. (UIAction and "yes" or "no"))
    System.LogAlways("[WitheringBrews]  - RegisterEventSystemListener: " .. f("RegisterEventSystemListener"))
    System.LogAlways("[WitheringBrews]  - RegisterEventMovieListener: " .. f("RegisterEventMovieListener"))
    System.LogAlways("[WitheringBrews]  - RegisterFSCommandListener: " .. f("RegisterFSCommandListener"))
    System.LogAlways("[WitheringBrews]  - RegisterElementListener: " .. f("RegisterElementListener"))
end

-- --- Bootstrap --------------------------------------------------------------
function WitheringBrews_Cmd_BootstrapPreview()
    local C = WB.Config or {}; local prev = C.DryRun
    WB.Config.DryRun = true
    System.LogAlways("[WitheringBrews] Bootstrap PREVIEW (DryRun=true)")
    WB.BuildPotionIndex()
    WB.BootstrapIfNeeded()
    WB.Config.DryRun = prev
end

function WitheringBrews_Cmd_BootstrapApply()
    local C = WB.Config or {}; local prev = C.DryRun
    WB.Config.DryRun = false
    System.LogAlways("[WitheringBrews] Bootstrap APPLY (DryRun=false)")
    WB.BuildPotionIndex()
    WB.BootstrapIfNeeded()
    WB.Config.DryRun = prev
end

function WitheringBrews_Cmd_BootstrapReset()
    local db = WB.DB or (KCDUtils and KCDUtils.DB and KCDUtils.DB.Factory and KCDUtils.DB.Factory("witheringbrews"))
    if not db then
        System.LogAlways("[WitheringBrews] DB missing"); return
    end
    local flag = (WB.Config and WB.Config.Bootstrap and WB.Config.Bootstrap.db_flag) or "WB_Config:migrated_v1"
    db:Del(flag)
    System.LogAlways("[WitheringBrews] Bootstrap flag cleared; next run will execute again.")
end

-- --- Inventory / potions inspection ----------------------------------------
function WitheringBrews_Cmd_UtilWho()
    local p = U and U.Player and U.Player() or nil
    System.LogAlways("[WitheringBrews] UtilWho: player=" .. tostring(p and p.id or "nil"))
end

function WitheringBrews_Cmd_UtilSnap()
    local snap = U and U.InventorySnapshot and U.InventorySnapshot() or {}
    local nUnique, nTotal = 0, 0
    for _, q in pairs(snap) do
        nUnique = nUnique + 1; nTotal = nTotal + (tonumber(q) or 0)
    end
    System.LogAlways("[WitheringBrews] UtilSnap: unique=" .. nUnique .. ", total=" .. nTotal)
    local printed = 0
    for cid, qty in pairs(snap) do
        local tag = (U and U.IsPotionId and U.IsPotionId(cid)) and "POTION " or ""
        System.LogAlways(string.format("[WitheringBrews]   %s%s x%d", tag, cid, qty))
        printed = printed + 1; if printed >= 10 then break end
    end
end

function WitheringBrews_Cmd_ScanPotions()
    local snap = U and U.InventorySnapshot and U.InventorySnapshot(U.Player()) or {}
    WB.BuildPotionIndex(); local idx = WB._PotionIndex or {}
    local byFam, total = {}, 0
    for cid, qty in pairs(snap) do
        local e = idx[cid]
        if e then
            byFam[e.family] = (byFam[e.family] or 0) + (tonumber(qty) or 0); total = total + (tonumber(qty) or 0)
        end
    end
    System.LogAlways(("[WitheringBrews] ScanPotions: totalMatched=%d"):format(total))
    local printed = 0
    for fam, qty in pairs(byFam) do
        System.LogAlways(("[WitheringBrews]  - %s x%d"):format(fam, qty))
        printed = printed + 1; if printed >= 20 then break end
    end
    if printed == 0 then System.LogAlways("[WitheringBrews]  (no potions matched current families)") end
end

function WitheringBrews_Cmd_PotionsReload()
    Script.ReloadScript("scripts/WitheringBrews/Potions.lua")
    WitheringBrews.BuildPotionIndex()
    System.LogAlways("[WitheringBrews] Potions reloaded and index rebuilt.")
end

function WitheringBrews_Cmd_PotionAllow(cid)
    if not cid then
        System.LogAlways("[WitheringBrews] usage: wb_potion_allow <classId>")
        return
    end
    local C = WitheringBrews.Config; C.PotionWhitelist = C.PotionWhitelist or {}
    C.PotionWhitelist[cid] = true
    System.LogAlways("[WitheringBrews] whitelist + " .. cid)
end

function WitheringBrews_Cmd_PotionBlock(cid)
    if not cid then
        System.LogAlways("[WitheringBrews] usage: wb_potion_block <classId>")
        return
    end
    local C = WitheringBrews.Config; C.PotionWhitelist = C.PotionWhitelist or {}
    C.PotionWhitelist[cid] = nil
    System.LogAlways("[WitheringBrews] whitelist - " .. cid)
end

function WitheringBrews_Cmd_PotionList()
    local wl = (WitheringBrews.Config and WitheringBrews.Config.PotionWhitelist) or {}
    local n = 0; for _ in pairs(wl) do n = n + 1 end
    System.LogAlways("[WitheringBrews] whitelist entries: " .. n)
    local shown = 0
    for cid, _ in pairs(wl) do
        System.LogAlways("  " .. cid)
        shown = shown + 1; if shown >= 50 then break end
    end
end

function WitheringBrews_Cmd_WhitelistFromFamilies()
    local C = WitheringBrews.Config
    C.PotionWhitelist = C.PotionWhitelist or {}
    local fams = C.PotionFamilies or {}
    local n = 0
    for _, data in pairs(fams) do
        for _, id in ipairs(data.ids or {}) do
            C.PotionWhitelist[id] = true
            n = n + 1
        end
    end
    System.LogAlways(("[WitheringBrews] Whitelist populated from families: %d ids"):format(n))
end
