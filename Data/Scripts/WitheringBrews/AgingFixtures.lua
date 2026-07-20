-- Temporary Patch 4 runtime fixture support.
-- Remove this entire module after terminal tests pass.

WitheringBrews =
    WitheringBrews or {}

local WB = WitheringBrews

WB.AgingFixtures =
    WB.AgingFixtures or {}

local F = WB.AgingFixtures

local MARIGOLD_I =
    "b38c34b7-6016-4f64-9ba2-65e1ce31d4a1"

local MARIGOLD_II =
    "761f9e84-e07b-4b4b-9425-7681898abccd"

local MARIGOLD_III =
    "b4e0af8c-3ed7-40ed-8537-7772489832c8"

local MARIGOLD_IV =
    "c7022225-70b4-4bde-afe0-1d42763a2ecd"

local function fixtureLog(message)
    System.LogAlways(
        "[WitheringBrews/AgingFixture] "
        .. tostring(message)
    )
end

local function valuesEqual(left, right)
    if type(left) ~= type(right) then
        return false
    end

    if type(left) ~= "table" then
        return left == right
    end

    for key, value in pairs(left) do
        if not valuesEqual(
            value,
            right[key]
        ) then
            return false
        end
    end

    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end

    return true
end

local function validatorIsClean(summary)
    return type(summary) == "table"
        and (summary.missingQty or 0) == 0
        and (summary.excessQty or 0) == 0
        and (summary.invalidRows or 0) == 0
        and (summary.invalidLists or 0) == 0
        and (summary.futureRows or 0) == 0
        and (summary.preEpochRows or 0) == 0
end

local function installSingleCohortFixture(
    specification,
    confirmation
)
    local summary = {
        success = false,
        failureReason = nil,

        cohortWrites = 0,

        compensationAttempted = false,
        compensationCohortWrites = 0,
        compensationSucceeded = false,
    }

    if type(specification) ~= "table" then
        fixtureLog(
            "Fixture aborted: specification is unavailable"
        )

        return false, summary
    end

    if confirmation
        ~= specification.confirmation
    then
        fixtureLog(
            "Fixture aborted: explicit "
            .. tostring(
                specification.confirmation
            )
            .. " confirmation required"
        )

        return false, summary
    end

    if not (
        WB.Config
        and WB.Config.DryRun == false
    ) then
        fixtureLog(
            "Fixture aborted: DryRun must be false"
        )

        return false, summary
    end

    local execution =
        WB.AgingExecution

    if not (
        execution
        and type(
            execution.BuildPlayerTransaction
        ) == "function"
        and type(
            execution.RecheckPreconditions
        ) == "function"
        and type(
            execution.WriteCohortListVerified
        ) == "function"
        and type(
            execution.RestoreCohortState
        ) == "function"
        and type(
            execution.VerifyCohortState
        ) == "function"
    ) then
        fixtureLog(
            "Fixture aborted: aging execution APIs unavailable"
        )

        return false, summary
    end

    local baseline =
        execution.BuildPlayerTransaction()

    if not baseline.valid then
        fixtureLog(
            "Fixture aborted: baseline transaction is invalid"
        )

        for _, reason in ipairs(
            baseline.blockedReasons
        ) do
            fixtureLog(
                "  BLOCKED " .. tostring(reason)
            )
        end

        return false, summary
    end

    if #baseline.affectedClassIds ~= 0 then
        fixtureLog(
            ("Fixture aborted: baseline has affectedIds=%d; expected 0")
                :format(
                    #baseline.affectedClassIds
                )
        )

        return false, summary
    end

    local baselineOk,
        baselineReason =
        specification.validateBaseline(
            baseline
        )

    if not baselineOk then
        fixtureLog(
            "Fixture aborted: "
            .. tostring(baselineReason)
        )

        return false, summary
    end

    local precheckOk, precheck =
        execution.RecheckPreconditions(
            baseline
        )

    fixtureLog(
        ("Fixture precheck: valid=%s checkedIds=%d inventoryChecks=%d cohortChecks=%d writes=0")
            :format(
                tostring(precheckOk),
                precheck.checkedIds,
                precheck.inventoryChecks,
                precheck.cohortChecks
            )
    )

    if not precheckOk then
        fixtureLog(
            "Fixture aborted: precondition recheck failed"
        )

        for _, reason in ipairs(
            precheck.reasons
        ) do
            fixtureLog(
                "  " .. tostring(reason)
            )
        end

        return false, summary
    end

    local expectedList,
        expectedReason =
        specification.buildExpectedList(
            baseline
        )

    if type(expectedList) ~= "table" then
        fixtureLog(
            "Fixture aborted: "
            .. tostring(expectedReason)
        )

        return false, summary
    end

    local touchedClassId =
        specification.classId

    -- Treat the class as touched before attempting the
    -- write because a failing call may still mutate DB state.
    local writeOk, writeResult =
        execution.WriteCohortListVerified(
            touchedClassId,
            expectedList
        )

    summary.cohortWrites =
        writeResult
        and (
            writeResult.cohortWrites
            or 0
        )
        or 0

    fixtureLog(
        ("Fixture cohort write: success=%s id=%s expectedRows=%s expectedQty=%s writes=%d reason=%s")
            :format(
                tostring(writeOk),
                tostring(touchedClassId),
                tostring(
                    writeResult
                    and writeResult.expectedRows
                ),
                tostring(
                    writeResult
                    and writeResult.expectedQty
                ),
                summary.cohortWrites,
                tostring(
                    writeResult
                    and writeResult.reason
                )
            )
    )

    local failureReason = nil

    if not writeOk then
        failureReason =
            "cohort write failed: "
            .. tostring(
                writeResult
                and writeResult.reason
            )
    end

    if not failureReason then
        local callOk,
            validatorOk,
            validatorSummary =
            pcall(
                WB.CohortsValidatePlayer
            )

        if not callOk then
            failureReason =
                "cohort validator raised an error: "
                .. tostring(validatorOk)
        elseif validatorOk ~= true
            or not validatorIsClean(
                validatorSummary
            )
        then
            failureReason =
                "cohort validator reported inconsistencies"
        end
    end

    local fixtureTransaction = nil

    if not failureReason then
        fixtureTransaction =
            execution.BuildPlayerTransaction()

        local postOk, postReason =
            specification.validatePostTransaction(
                fixtureTransaction,
                expectedList
            )

        if not postOk then
            failureReason =
                tostring(postReason)
        end
    end

    if failureReason then
        summary.failureReason =
            failureReason

        summary.compensationAttempted = true

        fixtureLog(
            "Fixture FAILED: "
            .. tostring(failureReason)
        )

        local restoreOk, restoreResult =
            execution.RestoreCohortState(
                {
                    touchedClassId,
                },
                baseline.cohortListsBefore
            )

        summary.compensationCohortWrites =
            restoreResult.cohortWrites

        local cohortsBeforeOk =
            execution.VerifyCohortState(
                baseline.configuredClassIds,
                baseline.cohortListsBefore
            )

        local restoredTransaction =
            execution.BuildPlayerTransaction()

        local transactionRestored =
            restoredTransaction.valid
            and #restoredTransaction.affectedClassIds
                == 0

        summary.compensationSucceeded =
            restoreOk
            and cohortsBeforeOk
            and transactionRestored

        fixtureLog(
            ("Fixture compensation: valid=%s writes=%d")
                :format(
                    tostring(
                        summary.compensationSucceeded
                    ),
                    summary.compensationCohortWrites
                )
        )

        if not summary.compensationSucceeded then
            fixtureLog(
                "CRITICAL: FIXTURE COMPENSATION FAILED"
            )
        end

        return false, summary
    end

    summary.success = true

    fixtureLog(
        tostring(
            specification.successMessage
        )
    )

    return true, summary
end

function F.InstallTerminalKeepFixture(confirmation)
    local fixtureCreatedAt = nil

    return installSingleCohortFixture(
        {
            confirmation =
                "INSTALL_TERMINAL_KEEP",

            classId =
                MARIGOLD_I,

            validateBaseline =
                function(baseline)
                    local inventory =
                        baseline.inventoryBefore

                    if inventory[MARIGOLD_I] ~= 1
                        or inventory[MARIGOLD_II]
                            ~= 3
                        or inventory[MARIGOLD_III]
                            ~= 0
                        or inventory[MARIGOLD_IV]
                            ~= 0
                    then
                        return false,
                            ("expected Marigold I=1 II=3 III=0 IV=0; actual I=%s II=%s III=%s IV=%s")
                                :format(
                                    tostring(
                                        inventory[
                                            MARIGOLD_I
                                        ]
                                    ),
                                    tostring(
                                        inventory[
                                            MARIGOLD_II
                                        ]
                                    ),
                                    tostring(
                                        inventory[
                                            MARIGOLD_III
                                        ]
                                    ),
                                    tostring(
                                        inventory[
                                            MARIGOLD_IV
                                        ]
                                    )
                                )
                    end

                    local list =
                        baseline.cohortListsBefore[
                            MARIGOLD_I
                        ]

                    if type(list) ~= "table"
                        or #list ~= 1
                        or list[1].qty ~= 1
                    then
                        return false,
                            "expected exactly one Marigold I cohort with qty=1"
                    end

                    if type(baseline.currentTime)
                        ~= "number"
                        or baseline.currentTime
                            < (1.5 * 86400)
                    then
                        return false,
                            "world time is too early for terminal fixture"
                    end

                    return true
                end,

            buildExpectedList =
                function(baseline)
                    fixtureCreatedAt =
                        baseline.currentTime
                        - (1.5 * 86400)

                    return {
                        {
                            qty = 1,
                            created_at =
                                fixtureCreatedAt,
                            source =
                                "fixture:terminal_keep",
                        },
                    }
                end,

            validatePostTransaction =
                function(
                    transaction,
                    expectedList
                )
                    if not transaction.valid then
                        return false,
                            "terminal keep transaction is invalid"
                    end

                    if #transaction.affectedClassIds
                        ~= 0
                    then
                        return false,
                            ("terminal keep expected affectedIds=0; actual=%d")
                                :format(
                                    #transaction.affectedClassIds
                                )
                    end

                    local txSummary =
                        transaction.summary

                    if txSummary.sourceRows ~= 4
                        or txSummary.stableRows ~= 3
                        or txSummary.terminalRows ~= 1
                        or txSummary.removals ~= 0
                        or txSummary.additions ~= 0
                    then
                        return false,
                            ("terminal keep summary differs: sourceRows=%d stableRows=%d terminalRows=%d removals=%d additions=%d")
                                :format(
                                    txSummary.sourceRows,
                                    txSummary.stableRows,
                                    txSummary.terminalRows,
                                    txSummary.removals,
                                    txSummary.additions
                                )
                    end

                    if not valuesEqual(
                        transaction.cohortListsBefore[
                            MARIGOLD_I
                        ],
                        expectedList
                    ) or not valuesEqual(
                        transaction.cohortListsExpected[
                            MARIGOLD_I
                        ],
                        expectedList
                    ) then
                        return false,
                            "terminal keep did not preserve the original cohort exactly"
                    end

                    local matchingPlan = nil

                    for _, rowPlan in ipairs(
                        transaction.rowPlans
                    ) do
                        if rowPlan.sourceClassId
                            == MARIGOLD_I
                        then
                            matchingPlan =
                                rowPlan.plan

                            break
                        end
                    end

                    if not matchingPlan
                        or matchingPlan.status
                            ~= "terminal"
                        or matchingPlan.sourceTier
                            ~= 1
                        or matchingPlan.targetTier
                            ~= 1
                        or matchingPlan.targetClassId
                            ~= MARIGOLD_I
                        or matchingPlan.requiresReplacement
                            ~= false
                        or matchingPlan.targetCreatedAt
                            ~= fixtureCreatedAt
                    then
                        return false,
                            "Marigold I planner row is not an exact terminal keep no-op"
                    end

                    return true
                end,

            successMessage =
                "Terminal keep fixture installed: valid=true sourceRows=4 stableRows=3 terminalRows=1 affectedIds=0 removals=0 additions=0 expectedWrites=0",
        },
        confirmation
    )
end

function F.InstallTerminalOverflowFixture(confirmation)
    local overflowCreatedAt = nil
    local targetCreatedAt = nil
    local originalMarigoldIList = nil

    return installSingleCohortFixture(
        {
            confirmation =
                "INSTALL_TERMINAL_OVERFLOW",

            classId =
                MARIGOLD_II,

            validateBaseline =
                function(baseline)
                    local inventory =
                        baseline.inventoryBefore

                    if inventory[MARIGOLD_I] ~= 1
                        or inventory[MARIGOLD_II]
                            ~= 3
                        or inventory[MARIGOLD_III]
                            ~= 0
                        or inventory[MARIGOLD_IV]
                            ~= 0
                    then
                        return false,
                            ("expected Marigold I=1 II=3 III=0 IV=0; actual I=%s II=%s III=%s IV=%s")
                                :format(
                                    tostring(
                                        inventory[
                                            MARIGOLD_I
                                        ]
                                    ),
                                    tostring(
                                        inventory[
                                            MARIGOLD_II
                                        ]
                                    ),
                                    tostring(
                                        inventory[
                                            MARIGOLD_III
                                        ]
                                    ),
                                    tostring(
                                        inventory[
                                            MARIGOLD_IV
                                        ]
                                    )
                                )
                    end

                    local listI =
                        baseline.cohortListsBefore[
                            MARIGOLD_I
                        ]

                    local listII =
                        baseline.cohortListsBefore[
                            MARIGOLD_II
                        ]

                    if type(listI) ~= "table"
                        or #listI ~= 1
                        or listI[1].qty ~= 1
                    then
                        return false,
                            "expected exactly one existing Marigold I cohort with qty=1"
                    end

                    if type(listII) ~= "table"
                        or #listII ~= 1
                        or listII[1].qty ~= 3
                    then
                        return false,
                            "expected exactly one Marigold II cohort with qty=3"
                    end

                    if type(baseline.currentTime)
                        ~= "number"
                        or baseline.currentTime
                            < (3.5 * 86400)
                    then
                        return false,
                            "world time is too early for terminal overflow fixture"
                    end

                    originalMarigoldIList =
                        listI

                    return true
                end,

            buildExpectedList =
                function(baseline)
                    -- II duration is two days and I duration
                    -- is one day. An age of 3.5 days reaches
                    -- I and exceeds its terminal threshold.
                    overflowCreatedAt =
                        baseline.currentTime
                        - (3.5 * 86400)

                    -- Time when the transformed cohort entered I.
                    targetCreatedAt =
                        baseline.currentTime
                        - (1.5 * 86400)

                    return {
                        {
                            qty = 3,
                            created_at =
                                overflowCreatedAt,
                            source =
                                "fixture:terminal_overflow",
                        },
                    }
                end,

            validatePostTransaction =
                function(
                    transaction,
                    expectedList
                )
                    if not transaction.valid then
                        return false,
                            "terminal overflow transaction is invalid"
                    end

                    if #transaction.affectedClassIds
                        ~= 2
                    then
                        return false,
                            ("terminal overflow expected affectedIds=2; actual=%d")
                                :format(
                                    #transaction.affectedClassIds
                                )
                    end

                    local txSummary =
                        transaction.summary

                    if txSummary.sourceRows ~= 4
                        or txSummary.removals ~= 3
                        or txSummary.additions ~= 3
                        or txSummary.terminalRows < 1
                    then
                        return false,
                            ("terminal overflow summary differs: sourceRows=%d stableRows=%d terminalRows=%d removals=%d additions=%d")
                                :format(
                                    txSummary.sourceRows,
                                    txSummary.stableRows,
                                    txSummary.terminalRows,
                                    txSummary.removals,
                                    txSummary.additions
                                )
                    end

                    if transaction.inventoryBefore[
                        MARIGOLD_I
                    ] ~= 1
                        or transaction.inventoryExpected[
                            MARIGOLD_I
                        ] ~= 4
                        or transaction.inventoryBefore[
                            MARIGOLD_II
                        ] ~= 3
                        or transaction.inventoryExpected[
                            MARIGOLD_II
                        ] ~= 0
                    then
                        return false,
                            "terminal overflow inventory state differs from I 1->4 and II 3->0"
                    end

                    if (
                        transaction.removalsByClassId[
                            MARIGOLD_II
                        ] or 0
                    ) ~= 3
                        or (
                            transaction.additionsByClassId[
                                MARIGOLD_I
                            ] or 0
                        ) ~= 3
                    then
                        return false,
                            "terminal overflow removal/addition quantities differ from expected"
                    end

                    if (
                        transaction.netInventoryDeltaByClassId[
                            MARIGOLD_I
                        ] or 0
                    ) ~= 3
                        or (
                            transaction.netInventoryDeltaByClassId[
                                MARIGOLD_II
                            ] or 0
                        ) ~= -3
                    then
                        return false,
                            "terminal overflow net inventory deltas differ from expected"
                    end

                    if not valuesEqual(
                        transaction.cohortListsBefore[
                            MARIGOLD_II
                        ],
                        expectedList
                    ) then
                        return false,
                            "stored Marigold II overflow cohort differs from fixture"
                    end

                    if not valuesEqual(
                        transaction.cohortListsExpected[
                            MARIGOLD_II
                        ],
                        {}
                    ) then
                        return false,
                            "expected final Marigold II cohort list is not empty"
                    end

                    local expectedI =
                        transaction.cohortListsExpected[
                            MARIGOLD_I
                        ]

                    if type(expectedI) ~= "table"
                        or #expectedI ~= 2
                    then
                        return false,
                            "expected final Marigold I list does not contain two distinct rows"
                    end

                    local preservedExisting = false
                    local foundOverflowTarget = false

                    for _, row in ipairs(expectedI) do
                        if valuesEqual(
                            row,
                            originalMarigoldIList[1]
                        ) then
                            preservedExisting = true
                        end

                        if row.qty == 3
                            and row.created_at
                                == targetCreatedAt
                            and row.source
                                == "fixture:terminal_overflow"
                        then
                            foundOverflowTarget = true
                        end
                    end

                    if not preservedExisting then
                        return false,
                            "existing Marigold I cohort was not preserved exactly"
                    end

                    if not foundOverflowTarget then
                        return false,
                            "transformed terminal Marigold I cohort is missing or incorrect"
                    end

                    local matchingPlan = nil

                    for _, rowPlan in ipairs(
                        transaction.rowPlans
                    ) do
                        if rowPlan.sourceClassId
                            == MARIGOLD_II
                        then
                            matchingPlan =
                                rowPlan.plan

                            break
                        end
                    end

                    if not matchingPlan
                        or matchingPlan.status
                            ~= "terminal"
                        or matchingPlan.sourceTier
                            ~= 2
                        or matchingPlan.targetTier
                            ~= 1
                        or matchingPlan.targetClassId
                            ~= MARIGOLD_I
                        or matchingPlan.requiresReplacement
                            ~= true
                        or matchingPlan.qty ~= 3
                        or matchingPlan.targetCreatedAt
                            ~= targetCreatedAt
                        or matchingPlan.originalSource
                            ~= "fixture:terminal_overflow"
                    then
                        return false,
                            "Marigold II planner row is not the expected terminal replacement"
                    end

                    return true
                end,

            successMessage =
                "Terminal overflow fixture installed: valid=true affectedIds=2 removeII=3 addI=3 expectedI=1->4 expectedIRows=2 expectedIITargetRows=0",
        },
        confirmation
    )
end