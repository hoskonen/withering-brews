-- [scripts/WitheringBrews/Core.lua]
WitheringBrews                     = WitheringBrews or {}
local WB                           = WitheringBrews

WB.Config                          = WB.Config or { Version = "0.0.1-dev" }
WB._registered                     = WB._registered or false
WB._ready                          = WB._ready or false

WitheringBrews._loot_open_snapshot = nil

-- Logging & DB -----------------------------------------------------------
local function LOG(m)
    if WB.Logger and WB.Logger.Warn then WB.Logger:Warn(m) else System.LogAlways("[WitheringBrews] " .. m) end
end

local function ensureDB()
    if not WB.DB and KCDUtils and KCDUtils.DB and KCDUtils.DB.Factory then
        WB.DB = KCDUtils.DB.Factory("witheringbrews")
    end
    return WB.DB
end

local function getWorldTime()
    if WB.Clock and type(WB.Clock.Now) == "function" then
        local value = WB.Clock.Now()

        if type(value) == "number" then
            return math.floor(value)
        end
    end

    return nil
end

-- --- KCDUtils handshake (attach logger + DB) --------------------------------
function WB.Handshake(maxTries, delayMs)
    WB._handshakeCalls = (WB._handshakeCalls or 0) + 1
    if WB._registered then return end
    maxTries, delayMs = maxTries or 50, delayMs or 100
    local tries = 0
    local function tick()
        if not WB._registered and KCDUtils and KCDUtils.RegisterMod then
            local mod = KCDUtils.RegisterMod({ Name = "witheringbrews" })
            WB.Logger = mod.Logger
            WB._registered = true
            ensureDB(); LOG(("WitheringBrews registered v%s"):format(WB.Config.Version))
            -- replay once in case gameplay already started before attach
            WB._handshakeReplayCalls = (WB._handshakeReplayCalls or 0) + 1
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

-- Lifecycle
function WB:OnGameplayStarted()
    WB._gameplayStartedCalls = (WB._gameplayStartedCalls or 0) + 1

    local firstInitialization = not WB._ready

    -- Process-level registration
    if not WB._registered then
        if not (KCDUtils and KCDUtils.RegisterMod) then
            LOG("OnGameplayStarted: KCDUtils unavailable; initialization deferred")
            return
        end

        local mod = KCDUtils.RegisterMod({ Name = "witheringbrews" })
        if not mod then
            LOG("OnGameplayStarted: KCDUtils registration failed; initialization deferred")
            return
        end

        WB.Logger = mod.Logger
        WB._registered = true
    end

    -- Save-session dependencies
    local db = ensureDB()
    if not db then
        LOG("OnGameplayStarted: DB unavailable; initialization deferred")
        return
    end

    local player = self.Util and self.Util.Player and self.Util.Player()
    if not player then
        LOG("OnGameplayStarted: player unavailable; initialization deferred")
        return
    end

    -- Run the DB smoke test only once per game process.
    if firstInitialization then
        db:Set("WB_Config:ping", {
            t = os.time(),
            note = "hello-db",
        })

        LOG("DB smoke: read " ..
            (db:Get("WB_Config:ping") and "OK" or "nil"))

        db:Del("WB_Config:ping")

        LOG("DB smoke: delete " ..
            (db:Get("WB_Config:ping") == nil and "OK" or "FAILED"))
    end

    -- Must not survive an in-process save load.
    self._loot_open_snapshot = nil

    self.BuildPotionIndex()
    self.BootstrapIfNeeded()

    -- Mark ready only after successful save-session initialization.
    WB._ready = true

    if firstInitialization then
        LOG(("OnGameplayStarted → ready (v%s)")
            :format(self.Config.Version or "?"))
    else
        LOG("OnGameplayStarted → save session reinitialized")
    end
end

-- Public stubs (filled next passes) --------------------------------------
function WB.RegisterNewStacks(ctx) LOG("RegisterNewStacks (stub)") end

function WB.AgeAndDowngrade() LOG("AgeAndDowngrade (stub)") end

function WB.Tick(ctx)
    WB.RegisterNewStacks(ctx); WB.AgeAndDowngrade()
end

function WB.GetTrackedPotion(classId)
    if type(classId) ~= "string" then
        return nil
    end

    -- Normally built during save initialization, but keep this helper robust
    -- when called manually during development.
    if not WB._PotionIndex and type(WB.BuildPotionIndex) == "function" then
        WB.BuildPotionIndex()
    end

    local entry = WB._PotionIndex and WB._PotionIndex[classId]
    if not entry then
        return nil
    end

    local config = WB.Config or {}
    local trackMode = config.TrackMode

    if trackMode == "families" then
        return entry
    end

    if trackMode == "whitelist" then
        local whitelist = config.PotionWhitelist or {}

        if whitelist[classId] == true then
            return entry
        end

        return nil
    end

    -- Invalid configuration should fail closed.
    return nil
end

-- --- ItemTransfer (primary anchor) ------------------------------------------
function WB:OnItemTransferOpened(...)
    WB._itemTransferOpenedCalls =
        (WB._itemTransferOpenedCalls or 0) + 1

    System.LogAlways(
        "[WitheringBrews] ItemTransfer opened (EL)"
    )

    local U = self.Util

    self.BuildPotionIndex()

    self._loot_open_snapshot =
        U
        and U.InventorySnapshot
        and U.InventorySnapshot(
            U.Player and U.Player() or nil
        )
        or {}

    System.LogAlways(string.format(
        "[WitheringBrews] LootOpen snapshot: kinds=%d",
        (function(t)
            local count = 0

            for _ in pairs(t or {}) do
                count = count + 1
            end

            return count
        end)(self._loot_open_snapshot)
    ))
end

function WB:OnItemTransferClosed(...)
    WB._itemTransferClosedCalls = (WB._itemTransferClosedCalls or 0) + 1
    System.LogAlways("[WitheringBrews] ItemTransfer closed (EL) → diff + cohorts")
    local U, D = self.Util, self.Debug
    if not self._loot_open_snapshot then
        if D and D.warn then D.warn("No open snapshot; skipping diff") end
        return
    end
    local after = U and U.InventorySnapshot and U.InventorySnapshot(U.Player and U.Player() or nil) or {}
    local added, removed = U.DiffCounts(self._loot_open_snapshot, after)
    self._loot_open_snapshot = nil

    local totalAdded = 0
    local dryRun = not (self.Config and self.Config.DryRun == false)
    local acquiredAt = nil

    if not dryRun then
        acquiredAt = getWorldTime()

        if type(acquiredAt) ~= "number" then
            System.LogAlways(
                "[WitheringBrews][WARN] ItemTransfer cohort writes skipped: world clock unavailable"
            )
        end
    end

    for cid, qty in pairs(added) do
        totalAdded = totalAdded + qty

        local e = self.GetTrackedPotion(cid)

        if e then
            local seedStatus

            if dryRun then
                seedStatus = "WOULD seed"
            elseif type(acquiredAt) == "number" then
                seedStatus = "seed"
            else
                seedStatus = "SKIP seed; world clock unavailable"
            end

            System.LogAlways(string.format(
                "[WitheringBrews] Loot delta: POTION %s (family=%s tier=%s band=%s) +%d (%s)",
                cid,
                e.family,
                ({ "i", "ii", "iii", "iv", "v" })[e.tier] or e.tier,
                e.band,
                qty,
                seedStatus
            ))

            if not dryRun
                and type(acquiredAt) == "number"
                and self.CohortsAdd
            then
                self.CohortsAdd(
                    cid,
                    qty,
                    acquiredAt,
                    "loot"
                )
            end
        else
            System.LogAlways(string.format(
                "[WitheringBrews] Loot delta: %s +%d (ignored; not tracked)",
                cid,
                qty
            ))
        end
    end
    System.LogAlways(string.format("[WitheringBrews] Loot delta summary: addedKinds=%d addedTotal=%d",
        (function(t)
            local c = 0; for _ in pairs(t) do c = c + 1 end; return c
        end)(added), totalAdded))
end

-- === Bootstrap (dry-run by default) ======================================
function WitheringBrews.BootstrapIfNeeded()
    local WB, C = WitheringBrews, WitheringBrews.Config or {}
    local D = WitheringBrews.Debug
    local B = C.Bootstrap or {}

    local function countKeys(t)
        local count = 0

        for _ in pairs(t or {}) do
            count = count + 1
        end

        return count
    end

    local function info(s) if D and D.info then D.info(s) else System.LogAlways("[WitheringBrews] " .. s) end end
    local function warn(s) if D and D.warn then D.warn(s) else System.LogAlways("[WitheringBrews][WARN] " .. s) end end

    info("Bootstrap: enter")
    if B.enable == false then
        warn("Bootstrap: disabled via config"); info("Bootstrap: exit"); return
    end

    local db = WB.DB or (KCDUtils and KCDUtils.DB and KCDUtils.DB.Factory and KCDUtils.DB.Factory("witheringbrews"))
    if not db then
        warn("Bootstrap: DB not available; skipping"); info("Bootstrap: exit"); return
    end

    local FLAG = B.db_flag or "WB_Config:migrated_v1"
    if db:Get(FLAG) then
        info("Bootstrap: flag already set → nothing to do"); info("Bootstrap: exit"); return
    end

    -- Util presence
    local U = WitheringBrews.Util
    if not (U and U.InventorySnapshot and U.Player) then
        warn("Bootstrap: Util missing (Util.lua not loaded?)"); info("Bootstrap: exit"); return
    end

    -- Player entity
    local player = U.Player()
    
    if not player then
        warn("Bootstrap: no player entity; skipping")
        info("Bootstrap: exit")
        return
    end

    -- Build index (safe if empty)
    if not WB._PotionIndex then WB.BuildPotionIndex() end
    info("Bootstrap: potion index size=" ..
        tostring(WB._PotionIndex and (next(WB._PotionIndex) and "nonzero" or "zero") or "nil"))

    -- Snapshots (currently stubbed; fine)
    local maps = {}

    if (B.affect or {}).player ~= false then
        maps.player = U.InventorySnapshot(player)

        info(("Bootstrap: took player snapshot (size=%d)")
            :format(countKeys(maps.player)))
    end


    -- if (B.affect or {}).stash == true then
    --     info("Bootstrap: stash requested but not implemented; skipping")
    -- end

    local total_items, total_potions, cohort_rows_planned = 0, 0, 0
    local perBand = { water = 0, wine = 0, oil = 0, spirit = 0 }
    local dryRun = (C.DryRun ~= false)
    local DAY = 24 * 60 * 60
    local seed_cfg =
        (C.Bootstrap and C.Bootstrap.seed_age_days)
        or {}

    local bootstrapNow = nil

    if not dryRun then
        bootstrapNow = getWorldTime()

        if type(bootstrapNow) ~= "number" then
            warn(
                "Bootstrap: world clock unavailable; "
                .. "refusing cohort writes"
            )
            info("Bootstrap: exit")
            return
        end

        if type(WB.CohortsAdd) ~= "function" then
            warn(
                "Bootstrap: CohortsAdd unavailable; "
                .. "refusing cohort writes"
            )
            info("Bootstrap: exit")
            return
        end
    end

    local function tierLabel(tier)
        return ({ "i", "ii", "iii", "iv", "v" })[tier]
            or tostring(tier)
    end

    local function seedAgeRange(band, tlabel)
        local bandCfg =
            seed_cfg[band]
            or seed_cfg.water
            or {}

        local range =
            bandCfg[tlabel]
            or { 0, 1 }

        local minimum =
            math.max(
                0,
                math.floor(tonumber(range[1]) or 0)
            )

        local maximum =
            math.max(
                0,
                math.floor(tonumber(range[2]) or minimum)
            )

        if maximum < minimum then
            maximum = minimum
        end

        return minimum, maximum
    end

    local function buildSeedBuckets(band, tlabel, quantity)
        local minimum, maximum =
            seedAgeRange(band, tlabel)

        local normalizedQuantity =
            math.max(
                0,
                math.floor(tonumber(quantity) or 0)
            )

        local buckets = {}

        for _ = 1, normalizedQuantity do
            local ageDays =
                minimum
                + math.floor(
                    math.random()
                    * (maximum - minimum + 1)
                )

            buckets[ageDays] =
                (buckets[ageDays] or 0) + 1
        end

        return buckets, normalizedQuantity
    end

    local function sortedBucketDays(buckets)
        local days = {}

        for ageDays in pairs(buckets or {}) do
            days[#days + 1] = ageDays
        end

        table.sort(days)

        return days
    end

    local function formatSeedBuckets(buckets, orderedDays)
        local parts = {}

        for _, ageDays in ipairs(orderedDays or {}) do
            parts[#parts + 1] =
                ("%dd x%d")
                    :format(
                        ageDays,
                        buckets[ageDays]
                    )
        end

        return table.concat(parts, ", ")
    end

    -- Iterate
    local matched_ids, matched_qty = 0, 0

    local okLoop, err = pcall(function()
        for scope, inventoryMap in pairs(maps) do
            local unique = 0

            for cid, rawQty in pairs(inventoryMap or {}) do
                unique = unique + 1

                local qty =
                    math.max(
                        0,
                        math.floor(tonumber(rawQty) or 0)
                    )

                total_items = total_items + qty

                local potion =
                    WB.GetTrackedPotion(cid)

                if potion and qty > 0 then
                    matched_ids = matched_ids + 1
                    matched_qty = matched_qty + qty
                    total_potions = total_potions + qty

                    perBand[potion.band] =
                        (perBand[potion.band] or 0) + qty

                    local label =
                        tierLabel(potion.tier)

                    local buckets =
                        buildSeedBuckets(
                            potion.band,
                            label,
                            qty
                        )

                    local orderedDays =
                        sortedBucketDays(buckets)

                    local rowCount =
                        #orderedDays

                    cohort_rows_planned =
                        cohort_rows_planned + rowCount

                    local action =
                        dryRun
                        and "WOULD seed"
                        or "seed"

                    info(
                        ("[Bootstrap] %s: %s (tier %s) "
                            .. "x%d → band=%s rows=%d "
                            .. "ages=[%s] (%s)")
                            :format(
                                scope,
                                potion.family,
                                label,
                                qty,
                                potion.band,
                                rowCount,
                                formatSeedBuckets(
                                    buckets,
                                    orderedDays
                                ),
                                action
                            )
                    )

                    if not dryRun then
                        local source =
                            "bootstrap:" .. scope

                        for _, ageDays in ipairs(orderedDays) do
                            local bucketQty =
                                buckets[ageDays]

                            local createdAt =
                                bootstrapNow
                                - ageDays * DAY

                            WB.CohortsAdd(
                                cid,
                                bucketQty,
                                createdAt,
                                source
                            )
                        end
                    end
                end
            end

            info(
                ("Bootstrap: scope=%s uniqueIds=%d")
                    :format(scope, unique)
            )
        end
    end)

    if not okLoop then
        warn(
            "Bootstrap: iteration error → "
            .. tostring(err)
        )
        info("Bootstrap: exit")
        return
    end

    info(
        ("[Bootstrap] matchedIds=%d matchedQty=%d")
            :format(
                matched_ids,
                matched_qty
            )
    )

    info(
        ("[Bootstrap] summary: scannedQty=%d "
            .. "potionQty=%d cohortRows=%d "
            .. "[water=%d wine=%d oil=%d spirit=%d] "
            .. "dryRun=%s")
            :format(
                total_items,
                total_potions,
                cohort_rows_planned,
                perBand.water or 0,
                perBand.wine or 0,
                perBand.oil or 0,
                perBand.spirit or 0,
                tostring(dryRun)
            )
    )

    if not dryRun then
        db:Set(FLAG, {
            t = bootstrapNow,
            time_source = "world",
            v = 1,
        })
        info("Bootstrap: flag set (migration complete).")
    else
        info("Bootstrap: DryRun=true → no cohorts written, no flag set.")
    end
    info("Bootstrap: exit")
end

-- --- Lookup and downgrade ------------------------------------------

-- Given a template UUID, return { family, tierIndex, band } or nil
function WitheringBrews.ResolvePotionById(tplId)
    local fams = WitheringBrews.Config.PotionFamilies or {}
    for family, data in pairs(fams) do
        for tier, id in ipairs(data.ids or {}) do
            if id == tplId then
                return family, tier, data.band
            end
        end
    end
    return nil, nil, nil
end

-- Given {family, tier}, return the UUID for a lower tier (or nil if already lowest)
function WitheringBrews.DowngradeId(family, tier)
    local fam = WitheringBrews.Config.PotionFamilies[family]
    if not fam or not fam.ids then return nil end
    local nextTier = math.max(1, math.min(#fam.ids, tier - 1))
    if nextTier == tier then return nil end
    return fam.ids[nextTier]
end

-- === Potion reverse index (UUID -> {family,tier,label,band}) ===============
function WitheringBrews.BuildPotionIndex()
    local WB = WitheringBrews
    local fams = (WB.Config and WB.Config.PotionFamilies) or {}
    local idx = {}
    for family, data in pairs(fams) do
        local band = data.band or "water"
        for tierIdx, id in ipairs(data.ids or {}) do
            local label = ({ "i", "ii", "iii", "iv", "v" })[tierIdx] or tostring(tierIdx)
            idx[id] = { family = family, tier = tierIdx, label = label, band = band }
        end
    end
    WB._PotionIndex = idx
end

-- --- Optional fades (kept tiny; harmless if they fire) ----------------------
function WB:OnHide(...) LOG("OnHide (fade)") end

function WB:OnShow(...) LOG("OnShow (fade)") end
