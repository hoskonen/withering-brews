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
local function now()
    if WB.Clock and type(WB.Clock.Now) == "function" then
        local value = WB.Clock.Now()

        if type(value) == "number" then
            return value
        end
    end

    return nil
end

function WB.CohortsGet(tpl)
    local db = ensureDB(); local list = db and db:Get(K_Stacks(tpl)); return list or {}
end

function WB.CohortsSet(tpl, list)
    local db = ensureDB(); if db then db:Set(K_Stacks(tpl), list) end
end

function WB.CohortsAdd(tpl, qty, created_at, source)
    qty = tonumber(qty) or 1

    local created = tonumber(created_at) or now()

    if type(created) ~= "number" then
        LOG(("CohortsAdd aborted: world clock unavailable tpl=%s")
            :format(tostring(tpl)))
        return false
    end

    local list = WB.CohortsGet(tpl)

    table.insert(list, {
        qty = qty,
        created_at = created,
        source = source or "unknown",
    })

    WB.CohortsSet(tpl, list)

    LOG(("CohortsAdd tpl=%s qty=%d created_at=%d source=%s")
        :format(
            tostring(tpl),
            qty,
            created,
            tostring(source)
        ))

    return true
end

function WB.CohortsTotalQty(tpl)
    local n = 0; for _, c in ipairs(WB.CohortsGet(tpl)) do n = n + (c.qty or 0) end; return n
end

-- '#' console helpers
function WB_CohAdd(tpl, qty, ageDays)
    if not tpl then
        System.LogAlways("[WitheringBrews] usage: # WB_CohAdd(\"<tpl>\", <qty>, <ageDays_optional>)"); return
    end
    local created = now()

    if type(created) ~= "number" then
        System.LogAlways(
            "[WitheringBrews] WB_CohAdd aborted: world clock unavailable"
        )
        return
    end

    if ageDays then
        created = created -
            math.floor((tonumber(ageDays) or 0) * 86400)
    end

    local added = WB.CohortsAdd(
        tpl,
        tonumber(qty) or 1,
        created,
        "console#"
    )

    if not added then
        return
    end

    System.LogAlways(
        ("[WitheringBrews] WB_CohAdd OK → tpl=%s total=%d")
            :format(tpl, WB.CohortsTotalQty(tpl))
    )
end

function WB_CohList(tpl)
    if not tpl then
        System.LogAlways("[WitheringBrews] usage: # WB_CohList(\"<tpl>\")"); return
    end
    local list = WB.CohortsGet(tpl)

    System.LogAlways(
        ("[WitheringBrews] WB_CohList tpl=%s count=%d")
            :format(tpl, #list)
    )

    local t = now()

    if type(t) ~= "number" then
        System.LogAlways(
            "[WitheringBrews] WB_CohList aborted: world clock unavailable"
        )
        return
    end

    for i, c in ipairs(list) do
        local created = tonumber(c.created_at)

        if created then
            local ageDays = (t - created) / 86400

            System.LogAlways(
                ("[WitheringBrews]   [%02d] qty=%d created_at=%d age=%.1f d src=%s")
                    :format(
                        i,
                        c.qty or 0,
                        created,
                        ageDays,
                        tostring(c.source or "?")
                    )
            )
        else
            System.LogAlways(
                ("[WitheringBrews]   [%02d] INVALID: missing created_at")
                    :format(i)
            )
        end
    end
end

function WB_CohClear(tpl)
    if not tpl then
        System.LogAlways("[WitheringBrews] usage: # WB_CohClear(\"<tpl>\")"); return
    end
    WB.CohortsSet(tpl, {}); System.LogAlways(("[WitheringBrews] WB_CohClear tpl=%s"):format(tpl))
end
