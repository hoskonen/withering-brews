-- Withering Brews: pure potion-aging calculations
--
-- This module must remain independent of inventory and LuaDB.
-- It receives all data through arguments and returns a plan.

WitheringBrews = WitheringBrews or {}

local WB = WitheringBrews

WB.Aging = WB.Aging or {}

local A = WB.Aging

local TIER_NAMES = {
    [1] = "i",
    [2] = "ii",
    [3] = "iii",
    [4] = "iv",
}

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isPositiveInteger(value)
    return isFiniteNumber(value)
        and value >= 1
        and math.floor(value) == value
end

local function isBootstrapSource(value)
    return type(value) == "string"
        and value:sub(1, 10) == "bootstrap:"
end

local function block(result, reason)
    result.status = "blocked"
    result.reason = tostring(reason)

    return result
end

local function getStageSeconds(rules, tier)
    if type(rules) ~= "table" then
        return nil
    end

    local durations = rules.stageSecondsByTier

    if type(durations) ~= "table" then
        return nil
    end

    local value = durations[tier]

    if value == nil then
        value = durations[TIER_NAMES[tier]]
    end

    value = tonumber(value)

    if not isFiniteNumber(value)
        or value <= 0
    then
        return nil
    end

    return value
end

function A.PlanCohort(
    familyName,
    familyData,
    sourceTier,
    cohort,
    currentTime,
    rules
)
    local result = {
        status = "blocked",
        reason = nil,

        family = familyName,
        band = nil,

        sourceTier = sourceTier,
        sourceClassId = nil,

        targetTier = nil,
        targetClassId = nil,

        qty = nil,

        originalCreatedAt = nil,
        targetCreatedAt = nil,

        originalSource = nil,

        elapsedSeconds = nil,
        consumedStageSeconds = nil,
        remainingAgeSeconds = nil,

        sourceStageSeconds = nil,
        targetStageSeconds = nil,

        tiersCrossed = 0,
        requiresReplacement = false,

        conditionRemaining = nil,
        conditionPercent = nil,

        terminalPolicy = nil,
        isTerminalTier = false,
        terminalExpired = false,
        terminalOverrunSeconds = 0,
    }

    if type(familyName) ~= "string"
        or familyName == ""
    then
        return block(
            result,
            "family name is missing"
        )
    end

    if type(familyData) ~= "table" then
        return block(
            result,
            "family data is missing"
        )
    end

    result.band = familyData.band

    local ids = familyData.ids

    if type(ids) ~= "table" then
        return block(
            result,
            "family ids are missing"
        )
    end

    sourceTier = tonumber(sourceTier)

    if not isPositiveInteger(sourceTier) then
        return block(
            result,
            "source tier must be a positive integer"
        )
    end

    result.sourceTier = sourceTier

    local sourceClassId = ids[sourceTier]

    if type(sourceClassId) ~= "string"
        or sourceClassId == ""
    then
        return block(
            result,
            ("source tier %d has no configured class ID")
                :format(sourceTier)
        )
    end

    result.sourceClassId = sourceClassId

    if type(cohort) ~= "table" then
        return block(
            result,
            "cohort is missing"
        )
    end

    local qty = cohort.qty
    local createdAt = cohort.created_at
    local source = cohort.source

    if not isPositiveInteger(qty) then
        return block(
            result,
            "cohort qty must be a positive integer"
        )
    end

    result.qty = qty

    if not isFiniteNumber(currentTime) then
        return block(
            result,
            "current time must be numeric"
        )
    end

    if not isFiniteNumber(createdAt) then
        return block(
            result,
            "created_at must be numeric"
        )
    end

    if createdAt < 0
        and not isBootstrapSource(source)
    then
        return block(
            result,
            "negative created_at requires bootstrap source"
        )
    end

    if createdAt > currentTime then
        return block(
            result,
            "created_at is in the future"
        )
    end

    if type(source) ~= "string"
        or source == ""
    then
        return block(
            result,
            "cohort source is missing"
        )
    end

    result.originalCreatedAt = createdAt
    result.originalSource = source

    local terminalPolicy =
        type(rules) == "table"
        and rules.terminalPolicy
        or nil

    terminalPolicy =
        terminalPolicy or "keep"

    result.terminalPolicy = terminalPolicy

    if terminalPolicy ~= "keep" then
        return block(
            result,
            "only terminal policy 'keep' is supported in Patch 3 Step 1"
        )
    end

    local sourceStageSeconds =
        getStageSeconds(
            rules,
            sourceTier
        )

    if not sourceStageSeconds then
        return block(
            result,
            ("missing or invalid duration for source tier %d")
                :format(sourceTier)
        )
    end

    result.sourceStageSeconds =
        sourceStageSeconds

    local elapsedSeconds =
        currentTime - createdAt

    local remainingAgeSeconds =
        elapsedSeconds

    local targetTier = sourceTier
    local tiersCrossed = 0

    while true do
        local stageSeconds =
            getStageSeconds(
                rules,
                targetTier
            )

        if not stageSeconds then
            return block(
                result,
                ("missing or invalid duration for tier %d")
                    :format(targetTier)
            )
        end

        if remainingAgeSeconds
            < stageSeconds
        then
            local conditionRemaining =
                1
                - (
                    remainingAgeSeconds
                    / stageSeconds
                )

            result.status =
                tiersCrossed > 0
                and "downgrade"
                or "stable"

            result.targetTier = targetTier
            result.targetClassId =
                ids[targetTier]

            result.elapsedSeconds =
                elapsedSeconds

            result.consumedStageSeconds =
                elapsedSeconds
                - remainingAgeSeconds

            result.remainingAgeSeconds =
                remainingAgeSeconds

            result.targetCreatedAt =
                currentTime
                - remainingAgeSeconds

            result.targetStageSeconds =
                stageSeconds

            result.tiersCrossed =
                tiersCrossed

            result.requiresReplacement =
                tiersCrossed > 0

            result.conditionRemaining =
                conditionRemaining

            result.conditionPercent =
                conditionRemaining * 100

            result.isTerminalTier =
                targetTier == 1

            return result
        end

        if targetTier > 1 then
            local lowerTier =
                targetTier - 1

            local lowerClassId =
                ids[lowerTier]

            if type(lowerClassId) ~= "string"
                or lowerClassId == ""
            then
                return block(
                    result,
                    ("missing lower-tier mapping: tier %d -> tier %d")
                        :format(
                            targetTier,
                            lowerTier
                        )
                )
            end

            remainingAgeSeconds =
                remainingAgeSeconds
                - stageSeconds

            targetTier = lowerTier
            tiersCrossed =
                tiersCrossed + 1
        else
            result.status = "terminal"

            result.targetTier = 1
            result.targetClassId = ids[1]

            result.elapsedSeconds =
                elapsedSeconds

            result.consumedStageSeconds =
                elapsedSeconds
                - remainingAgeSeconds

            result.remainingAgeSeconds =
                remainingAgeSeconds

            -- Time when this cohort entered Quality I.
            result.targetCreatedAt =
                currentTime
                - remainingAgeSeconds

            result.targetStageSeconds =
                stageSeconds

            result.tiersCrossed =
                tiersCrossed

            result.requiresReplacement =
                tiersCrossed > 0

            result.conditionRemaining = 0
            result.conditionPercent = 0

            result.isTerminalTier = true
            result.terminalExpired = true

            result.terminalOverrunSeconds =
                remainingAgeSeconds
                - stageSeconds

            return result
        end
    end
end

-- Real-data rule resolution and read-only preview ----------------------------

local function agingLog(message)
    System.LogAlways(
        "[WitheringBrews/Aging] "
        .. tostring(message)
    )
end

local function tierLabel(tier)
    local name = TIER_NAMES[tier]

    if name then
        return string.upper(name)
    end

    return tostring(tier or "?")
end

local function configuredTierMultiplier(
    multipliers,
    tier
)
    if type(multipliers) ~= "table" then
        return nil
    end

    local value = multipliers[tier]

    if value == nil then
        value = multipliers[TIER_NAMES[tier]]
    end

    value = tonumber(value)

    if not isFiniteNumber(value)
        or value <= 0
    then
        return nil
    end

    return value
end

local function maximumConfiguredTier(ids)
    local maximum = 0

    if type(ids) ~= "table" then
        return maximum
    end

    for tier, classId in pairs(ids) do
        if isPositiveInteger(tier)
            and type(classId) == "string"
            and classId ~= ""
        then
            maximum = math.max(
                maximum,
                tier
            )
        end
    end

    return maximum
end

local function inspectDenseArray(list)
    if type(list) ~= "table" then
        return false, 0
    end

    local count = 0
    local maximumIndex = 0

    for key in pairs(list) do
        if not isPositiveInteger(key) then
            return false, count
        end

        count = count + 1

        maximumIndex = math.max(
            maximumIndex,
            key
        )
    end

    return maximumIndex == count, count
end

function A.ResolveRules(
    familyData,
    options
)
    if type(familyData) ~= "table" then
        return false,
            "family data is missing"
    end

    local ids = familyData.ids
    local band = familyData.band

    if type(ids) ~= "table" then
        return false,
            "family ids are missing"
    end

    if type(band) ~= "string"
        or band == ""
    then
        return false,
            "family preservation band is missing"
    end

    local config =
        WB.Config
        and WB.Config.Aging
        or nil

    if type(config) ~= "table" then
        return false,
            "aging configuration is missing"
    end

    local bandDurations =
        config.band_stage_days

    if type(bandDurations) ~= "table" then
        return false,
            "band stage durations are missing"
    end

    local baseStageDays =
        tonumber(bandDurations[band])

    if not isFiniteNumber(baseStageDays)
        or baseStageDays <= 0
    then
        return false,
            ("invalid stage duration for band '%s'")
                :format(tostring(band))
    end

    local durationMultiplier =
        options
        and tonumber(
            options.durationMultiplier
        )
        or 1

    if not isFiniteNumber(durationMultiplier)
        or durationMultiplier <= 0
    then
        return false,
            "duration multiplier must be positive"
    end

    local maximumTier =
        maximumConfiguredTier(ids)

    if maximumTier < 1 then
        return false,
            "family has no configured tiers"
    end

    local stageSecondsByTier = {}

    for tier = 1, maximumTier do
        local tierMultiplier =
            configuredTierMultiplier(
                config.tier_multipliers,
                tier
            )

        if not tierMultiplier then
            return false,
                ("invalid multiplier for tier %s")
                    :format(
                        tierLabel(tier)
                    )
        end

        local stageSeconds =
            math.floor(
                baseStageDays
                * tierMultiplier
                * durationMultiplier
                * 86400
                + 0.5
            )

        if stageSeconds < 1 then
            return false,
                ("resolved stage duration is invalid for tier %s")
                    :format(
                        tierLabel(tier)
                    )
        end

        stageSecondsByTier[tier] =
            stageSeconds
    end

    return true, {
        terminalPolicy =
            config.terminal_policy or "keep",

        stageSecondsByTier =
            stageSecondsByTier,

        profile =
            config.profile or "unknown",

        band =
            band,

        baseStageDays =
            baseStageDays,

        durationMultiplier =
            durationMultiplier,
    }
end

function A.PreviewPlayer()
    if type(WB.BuildPotionIndex) == "function" then
        WB.BuildPotionIndex()
    end

    local U = WB.Util

    if not (
        U
        and type(U.Player) == "function"
        and type(U.InventorySnapshot) == "function"
    ) then
        agingLog(
            "Preview aborted: inventory utilities unavailable"
        )

        return false
    end

    if type(WB.CohortsGet) ~= "function" then
        agingLog(
            "Preview aborted: cohort storage unavailable"
        )

        return false
    end

    local playerEntity = U.Player()

    if not playerEntity then
        agingLog(
            "Preview aborted: player unavailable"
        )

        return false
    end

    local currentTime =
        WB.Clock
        and type(WB.Clock.Now) == "function"
        and WB.Clock.Now()
        or nil

    if not isFiniteNumber(currentTime) then
        agingLog(
            "Preview aborted: world clock unavailable"
        )

        return false
    end

    local snapshot =
        U.InventorySnapshot(playerEntity)

    if type(snapshot) ~= "table" then
        agingLog(
            "Preview aborted: inventory snapshot failed"
        )

        return false
    end

    local entries = {}

    for classId in pairs(
        WB._PotionIndex or {}
    ) do
        local potion =
            type(WB.GetTrackedPotion) == "function"
            and WB.GetTrackedPotion(classId)
            or nil

        local familyData =
            potion
            and WB.Config
            and WB.Config.PotionFamilies
            and WB.Config.PotionFamilies[
                potion.family
            ]
            or nil

        if potion and familyData then
            entries[#entries + 1] = {
                classId = classId,
                potion = potion,
                familyData = familyData,
            }
        end
    end

    table.sort(entries, function(left, right)
        local leftFamily =
            tostring(
                left.potion.family or ""
            )

        local rightFamily =
            tostring(
                right.potion.family or ""
            )

        if leftFamily ~= rightFamily then
            return leftFamily < rightFamily
        end

        local leftTier =
            tonumber(left.potion.tier) or 0

        local rightTier =
            tonumber(right.potion.tier) or 0

        if leftTier ~= rightTier then
            return leftTier < rightTier
        end

        return left.classId
            < right.classId
    end)

    local summary = {
        trackedIds = #entries,
        activeIds = 0,
        balancedIds = 0,
        blockedIds = 0,

        cohortRows = 0,
        cohortQty = 0,

        stableRows = 0,
        downgradeRows = 0,
        terminalRows = 0,
        replacementRows = 0,
    }

    for _, entry in ipairs(entries) do
        local classId = entry.classId
        local potion = entry.potion
        local familyData =
            entry.familyData

        local inventoryQty =
            math.max(
                0,
                math.floor(
                    tonumber(
                        snapshot[classId]
                    ) or 0
                )
            )

        local readOk, cohortList =
            pcall(
                WB.CohortsGet,
                classId
            )

        local hasStoredRows =
            readOk
            and type(cohortList) == "table"
            and next(cohortList) ~= nil

        local active =
            inventoryQty > 0
            or hasStoredRows
            or not readOk
            or (
                readOk
                and type(cohortList) ~= "table"
            )

        if active then
            summary.activeIds =
                summary.activeIds + 1

            local blockedReasons = {}
            local plans = {}
            local cohortQty = 0
            local rowCount = 0

            if not readOk then
                blockedReasons[
                    #blockedReasons + 1
                ] =
                    "cohort read failed: "
                    .. tostring(cohortList)
            elseif type(cohortList) ~= "table" then
                blockedReasons[
                    #blockedReasons + 1
                ] =
                    "cohort value is not a table"
            else
                local dense, count =
                    inspectDenseArray(
                        cohortList
                    )

                rowCount = count

                if not dense then
                    blockedReasons[
                        #blockedReasons + 1
                    ] =
                        "cohort list is not a dense array"
                end
            end

            local rulesOk, rulesOrReason =
                A.ResolveRules(
                    familyData,
                    {
                        durationMultiplier = 1,
                    }
                )

            if not rulesOk then
                blockedReasons[
                    #blockedReasons + 1
                ] =
                    "rules unavailable: "
                    .. tostring(
                        rulesOrReason
                    )
            end

            if #blockedReasons == 0 then
                for rowIndex, cohort in ipairs(
                    cohortList
                ) do
                    local plan =
                        A.PlanCohort(
                            potion.family,
                            familyData,
                            potion.tier,
                            cohort,
                            currentTime,
                            rulesOrReason
                        )

                    if plan.status == "blocked" then
                        blockedReasons[
                            #blockedReasons + 1
                        ] =
                            ("row %d: %s")
                                :format(
                                    rowIndex,
                                    tostring(
                                        plan.reason
                                    )
                                )
                    else
                        cohortQty =
                            cohortQty
                            + plan.qty

                        plans[#plans + 1] = {
                            index = rowIndex,
                            plan = plan,
                        }
                    end
                end
            end

            if #blockedReasons == 0
                and cohortQty ~= inventoryQty
            then
                blockedReasons[
                    #blockedReasons + 1
                ] =
                    ("inventory/cohort mismatch: inventory=%d cohorts=%d; reconcile first")
                        :format(
                            inventoryQty,
                            cohortQty
                        )
            end

            summary.cohortRows =
                summary.cohortRows + rowCount

            summary.cohortQty =
                summary.cohortQty + cohortQty

            if #blockedReasons > 0 then
                summary.blockedIds =
                    summary.blockedIds + 1

                agingLog(
                    ("%s tier=%s id=%s BLOCKED")
                        :format(
                            tostring(
                                potion.family
                                or "?"
                            ),
                            tierLabel(
                                potion.tier
                            ),
                            tostring(classId)
                        )
                )

                agingLog(
                    ("  inventory=%d validCohorts=%d rows=%d")
                        :format(
                            inventoryQty,
                            cohortQty,
                            rowCount
                        )
                )

                for _, reason in ipairs(
                    blockedReasons
                ) do
                    agingLog(
                        "  " .. reason
                    )
                end
            else
                summary.balancedIds =
                    summary.balancedIds + 1

                local rules = rulesOrReason

                agingLog(
                    ("%s tier=%s id=%s band=%s profile=%s")
                        :format(
                            tostring(
                                potion.family
                                or "?"
                            ),
                            tierLabel(
                                potion.tier
                            ),
                            tostring(classId),
                            tostring(
                                familyData.band
                                or "?"
                            ),
                            tostring(
                                rules.profile
                                or "?"
                            )
                        )
                )

                agingLog(
                    ("  inventory=%d cohorts=%d rows=%d durationMultiplier=%.2f")
                        :format(
                            inventoryQty,
                            cohortQty,
                            rowCount,
                            rules.durationMultiplier
                        )
                )

                for _, plannedRow in ipairs(
                    plans
                ) do
                    local rowIndex =
                        plannedRow.index

                    local plan =
                        plannedRow.plan

                    local ageDays =
                        plan.elapsedSeconds
                        / 86400

                    local targetStageDays =
                        plan.targetStageSeconds
                        / 86400

                    if plan.status == "stable" then
                        summary.stableRows =
                            summary.stableRows + 1

                        agingLog(
                            ("  row=%d qty=%d age=%.2fd stage=%.2fd condition=%.1f%% STABLE source=%s")
                                :format(
                                    rowIndex,
                                    plan.qty,
                                    ageDays,
                                    targetStageDays,
                                    plan.conditionPercent,
                                    tostring(
                                        plan.originalSource
                                    )
                                )
                        )
                    elseif plan.status == "downgrade" then
                        summary.downgradeRows =
                            summary.downgradeRows + 1

                        summary.replacementRows =
                            summary.replacementRows + 1

                        agingLog(
                            ("  row=%d qty=%d age=%.2fd WOULD DOWNGRADE %s -> %s crossed=%d targetCondition=%.1f%%")
                                :format(
                                    rowIndex,
                                    plan.qty,
                                    ageDays,
                                    tierLabel(
                                        plan.sourceTier
                                    ),
                                    tierLabel(
                                        plan.targetTier
                                    ),
                                    plan.tiersCrossed,
                                    plan.conditionPercent
                                )
                        )

                        agingLog(
                            ("    targetId=%s targetCreatedAt=%s source=%s")
                                :format(
                                    tostring(
                                        plan.targetClassId
                                    ),
                                    tostring(
                                        plan.targetCreatedAt
                                    ),
                                    tostring(
                                        plan.originalSource
                                    )
                                )
                        )
                    elseif plan.status == "terminal" then
                        summary.terminalRows =
                            summary.terminalRows + 1

                        if plan.requiresReplacement then
                            summary.replacementRows =
                                summary.replacementRows
                                + 1

                            agingLog(
                                ("  row=%d qty=%d age=%.2fd WOULD DOWNGRADE %s -> I; terminal expired policy=%s")
                                    :format(
                                        rowIndex,
                                        plan.qty,
                                        ageDays,
                                        tierLabel(
                                            plan.sourceTier
                                        ),
                                        tostring(
                                            plan.terminalPolicy
                                        )
                                    )
                            )
                        else
                            agingLog(
                                ("  row=%d qty=%d age=%.2fd TERMINAL EXPIRED tier=I policy=%s")
                                    :format(
                                        rowIndex,
                                        plan.qty,
                                        ageDays,
                                        tostring(
                                            plan.terminalPolicy
                                        )
                                    )
                            )
                        end
                    end
                end
            end
        end
    end

    agingLog(
        ("Preview summary: trackedIds=%d activeIds=%d balancedIds=%d blockedIds=%d cohortRows=%d cohortQty=%d stableRows=%d downgradeRows=%d terminalRows=%d replacementRows=%d cohortWrites=0 inventoryWrites=0")
            :format(
                summary.trackedIds,
                summary.activeIds,
                summary.balancedIds,
                summary.blockedIds,
                summary.cohortRows,
                summary.cohortQty,
                summary.stableRows,
                summary.downgradeRows,
                summary.terminalRows,
                summary.replacementRows
            )
    )

    return true, summary
end

-- Real potion-data validation -----------------------------------------------

function A.ValidateConfiguredRules()
    if type(WB.BuildPotionIndex) == "function" then
        WB.BuildPotionIndex()
    end

    local families =
        WB.Config
        and WB.Config.PotionFamilies
        or nil

    if type(families) ~= "table" then
        agingLog(
            "Rule validation aborted: PotionFamilies unavailable"
        )

        return false, {
            families = 0,
            passed = 0,
            failed = 1,
            writes = 0,
        }
    end

    local familyNames = {}

    for familyName in pairs(families) do
        familyNames[#familyNames + 1] =
            familyName
    end

    table.sort(familyNames)

    local summary = {
        families = #familyNames,
        passed = 0,
        failed = 0,
        classIds = 0,
        boundaryTests = 0,
        writes = 0,
    }

    local classIdOwners = {}

    -- Keep the synthetic clock comfortably above the longest configured
    -- stage while preserving one-second precision in the game Lua runtime.
    local currentTime = 2000000

    agingLog(
        ("Validating configured aging rules: families=%d")
            :format(summary.families)
    )

    for _, familyName in ipairs(familyNames) do
        local familyData =
            families[familyName]

        local failures = {}

        local ids =
            type(familyData) == "table"
            and familyData.ids
            or nil

        local maximumTier =
            maximumConfiguredTier(ids)

        local dense, tierCount =
            inspectDenseArray(ids)

        if type(familyData) ~= "table" then
            failures[#failures + 1] =
                "family data is not a table"
        end

        if type(ids) ~= "table" then
            failures[#failures + 1] =
                "ids table is missing"
        elseif not dense then
            failures[#failures + 1] =
                "tier IDs are not a dense array"
        elseif tierCount < 1 then
            failures[#failures + 1] =
                "family has no tier IDs"
        end

        local rulesOk, rulesOrReason =
            A.ResolveRules(
                familyData,
                {
                    durationMultiplier = 1,
                }
            )

        if not rulesOk then
            failures[#failures + 1] =
                "rule resolution failed: "
                .. tostring(rulesOrReason)
        end

        if type(ids) == "table" then
            for tier = 1, maximumTier do
                local classId = ids[tier]

                if type(classId) ~= "string"
                    or classId == ""
                then
                    failures[#failures + 1] =
                        ("tier %s has no valid class ID")
                            :format(
                                tierLabel(tier)
                            )
                else
                    summary.classIds =
                        summary.classIds + 1

                    local previousOwner =
                        classIdOwners[classId]

                    if previousOwner then
                        failures[#failures + 1] =
                            ("class ID %s is also owned by %s tier %s")
                                :format(
                                    classId,
                                    previousOwner.family,
                                    tierLabel(
                                        previousOwner.tier
                                    )
                                )
                    else
                        classIdOwners[classId] = {
                            family = familyName,
                            tier = tier,
                        }
                    end

                    if type(WB.GetTrackedPotion) == "function" then
                        local indexed =
                            WB.GetTrackedPotion(classId)

                        if not indexed then
                            failures[#failures + 1] =
                                ("tier %s class ID is absent from potion index")
                                    :format(
                                        tierLabel(tier)
                                    )
                        elseif indexed.family ~= familyName
                            or tonumber(indexed.tier) ~= tier
                        then
                            failures[#failures + 1] =
                                ("tier %s index mismatch: family=%s tier=%s")
                                    :format(
                                        tierLabel(tier),
                                        tostring(
                                            indexed.family
                                        ),
                                        tostring(
                                            indexed.tier
                                        )
                                    )
                        end
                    end
                end
            end
        end

        if rulesOk and dense and tierCount >= 1 then
            local rules = rulesOrReason

            for sourceTier = 1, maximumTier do
                local stageSeconds =
                    rules.stageSecondsByTier[
                        sourceTier
                    ]

                if not isFiniteNumber(stageSeconds)
                    or stageSeconds <= 0
                then
                    failures[#failures + 1] =
                        ("tier %s resolved an invalid stage duration")
                            :format(
                                tierLabel(sourceTier)
                            )
                else
                    local beforeThreshold =
                        A.PlanCohort(
                            familyName,
                            familyData,
                            sourceTier,
                            {
                                qty = 1,
                                created_at =
                                    currentTime
                                    - (
                                        stageSeconds
                                        - 1
                                    ),
                                source =
                                    "rule-validation",
                            },
                            currentTime,
                            rules
                        )

                    summary.boundaryTests =
                        summary.boundaryTests + 1

                    if beforeThreshold.status ~= "stable"
                        or beforeThreshold.targetTier ~= sourceTier
                    then
                        failures[#failures + 1] =
                            ("tier %s failed pre-threshold boundary test: status=%s target=%s")
                                :format(
                                    tierLabel(sourceTier),
                                    tostring(
                                        beforeThreshold.status
                                    ),
                                    tierLabel(
                                        beforeThreshold.targetTier
                                    )
                                )
                    end

                    local exactThreshold =
                        A.PlanCohort(
                            familyName,
                            familyData,
                            sourceTier,
                            {
                                qty = 1,
                                created_at =
                                    currentTime
                                    - stageSeconds,
                                source =
                                    "rule-validation",
                            },
                            currentTime,
                            rules
                        )

                    summary.boundaryTests =
                        summary.boundaryTests + 1

                    if sourceTier > 1 then
                        if exactThreshold.status ~= "downgrade"
                            or exactThreshold.targetTier
                                ~= sourceTier - 1
                            or exactThreshold.requiresReplacement
                                ~= true
                        then
                            failures[#failures + 1] =
                                ("tier %s failed exact-threshold downgrade test: status=%s target=%s replacement=%s")
                                    :format(
                                        tierLabel(sourceTier),
                                        tostring(
                                            exactThreshold.status
                                        ),
                                        tierLabel(
                                            exactThreshold.targetTier
                                        ),
                                        tostring(
                                            exactThreshold.requiresReplacement
                                        )
                                    )
                        end
                    else
                        if exactThreshold.status ~= "terminal"
                            or exactThreshold.targetTier ~= 1
                            or exactThreshold.requiresReplacement
                                ~= false
                        then
                            failures[#failures + 1] =
                                ("tier I failed exact terminal test: status=%s target=%s replacement=%s")
                                    :format(
                                        tostring(
                                            exactThreshold.status
                                        ),
                                        tierLabel(
                                            exactThreshold.targetTier
                                        ),
                                        tostring(
                                            exactThreshold.requiresReplacement
                                        )
                                    )
                        end
                    end
                end
            end
        end

        if #failures == 0 then
            summary.passed =
                summary.passed + 1

            local rules = rulesOrReason
            local durations = {}

            for tier = maximumTier, 1, -1 do
                durations[#durations + 1] =
                    ("%s=%.2fd")
                        :format(
                            tierLabel(tier),
                            rules.stageSecondsByTier[tier]
                                / 86400
                        )
            end

            agingLog(
                ("%s OK band=%s tiers=%d %s")
                    :format(
                        familyName,
                        tostring(familyData.band),
                        maximumTier,
                        table.concat(
                            durations,
                            " "
                        )
                    )
            )
        else
            summary.failed =
                summary.failed + 1

            agingLog(
                ("%s FAILED band=%s tiers=%d")
                    :format(
                        tostring(familyName),
                        tostring(
                            type(familyData) == "table"
                            and familyData.band
                            or "?"
                        ),
                        maximumTier
                    )
            )

            for _, failure in ipairs(failures) do
                agingLog(
                    "  " .. tostring(failure)
                )
            end
        end
    end

    agingLog(
        ("Rule validation summary: families=%d passed=%d failed=%d classIds=%d boundaryTests=%d writes=0")
            :format(
                summary.families,
                summary.passed,
                summary.failed,
                summary.classIds,
                summary.boundaryTests
            )
    )

    return summary.failed == 0, summary
end

-- Pure synthetic test suite --------------------------------------------------

local function approximatelyEqual(
    left,
    right,
    tolerance
)
    tolerance = tolerance or 0.0001

    return math.abs(left - right)
        <= tolerance
end

function A.RunSelfTests()
    local currentTime = 1000

    local fourTierFamily = {
        band = "test",
        ids = {
            "tier-i",
            "tier-ii",
            "tier-iii",
            "tier-iv",
        },
    }

    local threeTierFamily = {
        band = "test",
        ids = {
            "tier-i",
            "tier-ii",
            "tier-iii",
        },
    }

    local oneTierFamily = {
        band = "test",
        ids = {
            "only-tier",
        },
    }

    local brokenFamily = {
        band = "test",
        ids = {
            [1] = "tier-i",
            [3] = "tier-iii",
        },
    }

    -- Lower qualities deliberately have shorter stages.
    local rules = {
        terminalPolicy = "keep",

        stageSecondsByTier = {
            [4] = 400,
            [3] = 300,
            [2] = 200,
            [1] = 100,
        },
    }

    local function cohortForAge(
        ageSeconds,
        source
    )
        return {
            qty = 2,
            created_at =
                currentTime - ageSeconds,

            source =
                source or "selftest",
        }
    end

    local tests = {}

    local function addTest(name, callback)
        tests[#tests + 1] = {
            name = name,
            callback = callback,
        }
    end

    addTest("fresh Quality IV is stable", function()
        local plan = A.PlanCohort(
            "test",
            fourTierFamily,
            4,
            cohortForAge(0),
            currentTime,
            rules
        )

        return plan.status == "stable"
            and plan.targetTier == 4
            and approximatelyEqual(
                plan.conditionPercent,
                100
            )
    end)

    addTest("just before Quality IV threshold", function()
        local plan = A.PlanCohort(
            "test",
            fourTierFamily,
            4,
            cohortForAge(399),
            currentTime,
            rules
        )

        return plan.status == "stable"
            and plan.targetTier == 4
            and plan.tiersCrossed == 0
    end)

    addTest("exact Quality IV threshold", function()
        local plan = A.PlanCohort(
            "test",
            fourTierFamily,
            4,
            cohortForAge(400),
            currentTime,
            rules
        )

        return plan.status == "downgrade"
            and plan.targetTier == 3
            and plan.tiersCrossed == 1
            and approximatelyEqual(
                plan.conditionPercent,
                100
            )
    end)

    addTest("Quality III uses its own duration", function()
        local plan = A.PlanCohort(
            "test",
            fourTierFamily,
            4,
            cohortForAge(550),
            currentTime,
            rules
        )

        return plan.status == "downgrade"
            and plan.targetTier == 3
            and plan.remainingAgeSeconds == 150
            and approximatelyEqual(
                plan.conditionPercent,
                50
            )
    end)

    addTest("multiple tiers carry overflow", function()
        local plan = A.PlanCohort(
            "test",
            fourTierFamily,
            4,
            cohortForAge(800),
            currentTime,
            rules
        )

        return plan.status == "downgrade"
            and plan.targetTier == 2
            and plan.tiersCrossed == 2
            and plan.remainingAgeSeconds == 100
            and approximatelyEqual(
                plan.conditionPercent,
                50
            )
    end)

    addTest("exact entry into Quality I", function()
        local plan = A.PlanCohort(
            "test",
            fourTierFamily,
            4,
            cohortForAge(900),
            currentTime,
            rules
        )

        return plan.status == "downgrade"
            and plan.targetTier == 1
            and plan.tiersCrossed == 3
            and approximatelyEqual(
                plan.conditionPercent,
                100
            )
    end)

    addTest("exact terminal expiry", function()
        local plan = A.PlanCohort(
            "test",
            fourTierFamily,
            4,
            cohortForAge(1000),
            currentTime,
            rules
        )

        return plan.status == "terminal"
            and plan.targetTier == 1
            and plan.requiresReplacement == true
            and plan.terminalExpired == true
            and plan.terminalOverrunSeconds == 0
            and plan.conditionPercent == 0
    end)

    addTest("one-tier potion before expiry", function()
        local plan = A.PlanCohort(
            "test",
            oneTierFamily,
            1,
            cohortForAge(99),
            currentTime,
            rules
        )

        return plan.status == "stable"
            and plan.targetTier == 1
            and plan.terminalExpired == false
    end)

    addTest("one-tier potion at expiry", function()
        local plan = A.PlanCohort(
            "test",
            oneTierFamily,
            1,
            cohortForAge(100),
            currentTime,
            rules
        )

        return plan.status == "terminal"
        and plan.targetTier == 1
        and plan.requiresReplacement == false
        and plan.terminalExpired == true
    end)

    addTest("three-tier family uses actual chain", function()
        local plan = A.PlanCohort(
            "test",
            threeTierFamily,
            3,
            cohortForAge(300),
            currentTime,
            rules
        )

        return plan.status == "downgrade"
            and plan.sourceTier == 3
            and plan.targetTier == 2
            and plan.tiersCrossed == 1
    end)

    addTest("missing lower-tier mapping blocks", function()
        local plan = A.PlanCohort(
            "test",
            brokenFamily,
            3,
            cohortForAge(300),
            currentTime,
            rules
        )

        return plan.status == "blocked"
            and type(plan.reason) == "string"
            and plan.reason:find(
                "missing lower%-tier mapping"
            ) ~= nil
    end)

    addTest("negative bootstrap timestamp is valid", function()
        local plan = A.PlanCohort(
            "test",
            fourTierFamily,
            4,
            {
                qty = 1,
                created_at = -300,
                source = "bootstrap:player",
            },
            100,
            rules
        )

        return plan.status == "downgrade"
            and plan.targetTier == 3
    end)

    addTest("negative normal timestamp blocks", function()
        local plan = A.PlanCohort(
            "test",
            fourTierFamily,
            4,
            {
                qty = 1,
                created_at = -300,
                source = "loot",
            },
            100,
            rules
        )

        return plan.status == "blocked"
    end)

    local passed = 0
    local failed = 0

    for _, test in ipairs(tests) do
        local callOk, testPassed =
            pcall(test.callback)

        if callOk and testPassed then
            passed = passed + 1

            System.LogAlways(
                "[WitheringBrews/AgingTest] PASS "
                .. test.name
            )
        else
            failed = failed + 1

            System.LogAlways(
                "[WitheringBrews/AgingTest] FAIL "
                .. test.name
            )
        end
    end

    System.LogAlways(
        ("[WitheringBrews/AgingTest] Summary passed=%d failed=%d writes=0")
            :format(
                passed,
                failed
            )
    )

    return failed == 0, {
        passed = passed,
        failed = failed,
        writes = 0,
    }
end