Script.ReloadScript("scripts/WitheringBrews/Core.lua")
local WB = WitheringBrews
local function LOG(m) if WB.Logger and WB.Logger.Warn then WB.Logger:Warn(m) else System.LogAlways("[WitheringBrews] " ..
        m) end end

local function ensureDB()
    if not WB.DB and KCDUtils and KCDUtils.DB and KCDUtils.DB.Factory then
        WB.DB = KCDUtils.DB.Factory("witheringbrews")
    end
    return WB.DB
end

local function K_Stacks(tpl) return "WB_Stacks:" .. tostring(tpl) end
local function now() return os.time() end

function WB.CohortsGet(tpl)
    local db = ensureDB(); local list = db and db:Get(K_Stacks(tpl)); return list or {}
end

function WB.CohortsSet(tpl, list)
    local db = ensureDB(); if db then db:Set(K_Stacks(tpl), list) end
end

function WB.CohortsAdd(tpl, qty, created_at, source)
    qty = tonumber(qty) or 1
    local list = WB.CohortsGet(tpl)
    table.insert(list, { qty = qty, created_at = created_at or now(), source = source or "unknown" })
    WB.CohortsSet(tpl, list)
    LOG(("CohortsAdd tpl=%s qty=%d source=%s"):format(tostring(tpl), qty, tostring(source)))
end

function WB.CohortsTotalQty(tpl)
    local n = 0; for _, c in ipairs(WB.CohortsGet(tpl)) do n = n + (c.qty or 0) end; return n
end

-- '#' console helpers
function WB_CohAdd(tpl, qty, ageDays)
    if not tpl then
        System.LogAlways("[WitheringBrews] usage: # WB_CohAdd(\"<tpl>\", <qty>, <ageDays_optional>)"); return
    end
    local created = now(); if ageDays then created = created - math.floor((tonumber(ageDays) or 0) * 86400) end
    WB.CohortsAdd(tpl, tonumber(qty) or 1, created, "console#")
    System.LogAlways(("[WitheringBrews] WB_CohAdd OK → tpl=%s total=%d"):format(tpl, WB.CohortsTotalQty(tpl)))
end

function WB_CohList(tpl)
    if not tpl then
        System.LogAlways("[WitheringBrews] usage: # WB_CohList(\"<tpl>\")"); return
    end
    local list = WB.CohortsGet(tpl); System.LogAlways(("[WitheringBrews] WB_CohList tpl=%s count=%d"):format(tpl, #list))
    local t = now(); for i, c in ipairs(list) do
        local d = (t - (c.created_at or t)) / 86400
        System.LogAlways(("[WitheringBrews]   [%02d] qty=%d age=%.1f d src=%s"):format(i, c.qty or 0, d,
            tostring(c.source or "?")))
    end
end

function WB_CohClear(tpl)
    if not tpl then
        System.LogAlways("[WitheringBrews] usage: # WB_CohClear(\"<tpl>\")"); return
    end
    WB.CohortsSet(tpl, {}); System.LogAlways(("[WitheringBrews] WB_CohClear tpl=%s"):format(tpl))
end
