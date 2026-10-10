/**
 * Orchestrates one decision: read the portfolio, run the deterministic
 * engine, persist Decision__c and Action__c, and return the audit trail.
 */
public with sharing class RenewAIDecisionService {

    public static RenewAIDTO.DecisionResponse run(
        RenewAIDTO.DecisionRequest request,
        String correlationId
    ) {
        if (request == null) {
            throw validation(
                'request', 'REQUIRED', 'A decision request is required.');
        }

        String mode = String.isBlank(request.objectiveMode)
            ? 'Balanced'
            : request.objectiveMode;

        RenewAIDecisionEngine.Context ctx = loadContext(
            request.asOf,
            correlationId
        );

        return decideAndPersist(
            ctx, mode, correlationId, correlationId, null, null, null);
    }

    /**
     * Validates asOf, reads the portfolio and builds the engine context.
     * Public so the scenario service can reuse it.
     */
    public static RenewAIDecisionEngine.Context loadContext(
        Datetime asOf,
        String correlationId
    ) {
        RenewAIDTO.PortfolioRequest portfolioRequest =
            new RenewAIDTO.PortfolioRequest();
        portfolioRequest.asOf = asOf;
        portfolioRequest.intervalMinutes =
            RenewAIInputValidator.INTERVAL_MINUTES;
        portfolioRequest.maximumAgeMinutes =
            RenewAIInputValidator.MAX_AGE_MINUTES;
        RenewAIInputValidator.validateRequest(portfolioRequest);

        RenewAIDTO.PortfolioResponse portfolio =
            RenewAIPortfolioService.getPortfolio(
                portfolioRequest,
                correlationId
            );

        return buildContext(
            portfolio,
            asOf,
            portfolioRequest.maximumAgeMinutes
        );
    }

    /**
     * Runs the engine on a (possibly disturbed) context and saves the
     * Decision__c and Action__c rows. scenarioId, phase and stepIndex are
     * optional and only set for scenario runs.
     */
    public static RenewAIDTO.DecisionResponse decideAndPersist(
        RenewAIDecisionEngine.Context ctx,
        String mode,
        String correlationId,
        String decisionKey,
        Id scenarioId,
        String phase,
        Integer stepIndex
    ) {
        RenewAIDecisionEngine.EngineResult result =
            RenewAIDecisionEngine.decide(ctx, mode);

        return saveDecision(
            ctx, mode, correlationId, decisionKey,
            scenarioId, phase, stepIndex, result);
    }

    /**
     * Saves an engine result that was already computed (the simulation runs
     * the engine itself, then saves each step through here).
     */
    public static RenewAIDTO.DecisionResponse saveDecision(
        RenewAIDecisionEngine.Context ctx,
        String mode,
        String correlationId,
        String decisionKey,
        Id scenarioId,
        String phase,
        Integer stepIndex,
        RenewAIDecisionEngine.EngineResult result
    ) {
        Id decisionId = persist(
            ctx.asOf, mode, correlationId, decisionKey,
            scenarioId, phase, stepIndex, result);

        return toResponse(
            decisionId, correlationId, ctx.asOf, mode, ctx, result);
    }

    // ------------------------------------------------------------- context

    private static RenewAIDecisionEngine.Context buildContext(
        RenewAIDTO.PortfolioResponse portfolio,
        Datetime asOf,
        Integer maximumAgeMinutes
    ) {
        RenewAIDecisionEngine.Context ctx =
            new RenewAIDecisionEngine.Context();

        ctx.asOf = asOf;
        ctx.renewableMW = portfolio.metrics.renewableTotalMW;
        ctx.demandMW = portfolio.metrics.totalDemandMW;
        ctx.priceMWh = portfolio.metrics.energyPriceMWh;
        ctx.gridLimitMW = portfolio.metrics.gridCapacityMW;
        ctx.confidence = findConfidence(asOf, maximumAgeMinutes);

        for (RenewAIDTO.AssetSummary asset : portfolio.assets) {
            if (asset.assetType == 'Grid' && ctx.gridAssetCode == null) {
                ctx.gridAssetCode = asset.assetCode;
            }

            if (asset.assetType == 'Solar' && asset.generationMW != null) {
                ctx.solarMW += asset.generationMW;
            }

            if (asset.assetType == 'Battery') {
                Boolean available =
                    asset.status == 'Active' &&
                    asset.stateOfChargePercent != null &&
                    asset.stale != true;

                ctx.batteries.add(new RenewAIDecisionEngine.Battery(
                    asset.assetCode,
                    asset.capacityMW,
                    asset.stateOfChargePercent,
                    available
                ));
            }
        }

        return ctx;
    }

    // Forecast confidence = average weather score of the recent snapshots.
    private static Decimal findConfidence(
        Datetime asOf,
        Integer maximumAgeMinutes
    ) {
        Datetime oldestAccepted = asOf.addMinutes(-maximumAgeMinutes);

        List<AggregateResult> rows = [
            SELECT AVG(Weather_Score__c) averageScore
            FROM Operating_Snapshot__c
            WHERE Timestamp__c <= :asOf
            AND Timestamp__c >= :oldestAccepted
            AND Weather_Score__c != null
            WITH USER_MODE
        ];

        if (rows.isEmpty() || rows[0].get('averageScore') == null) {
            return 0.5;
        }

        Decimal average = Decimal.valueOf(
            String.valueOf(rows[0].get('averageScore'))
        );
        return Math.min(Math.max(average * 0.01, 0), 1);
    }

    // ------------------------------------------------------------- persist

    private static Id persist(
        Datetime asOf,
        String mode,
        String correlationId,
        String decisionKey,
        Id scenarioId,
        String phase,
        Integer stepIndex,
        RenewAIDecisionEngine.EngineResult result
    ) {
        Decision__c decision = new Decision__c(
            Decision_Key__c = decisionKey,
            Correlation_Id__c = correlationId,
            Decision_Type__c = result.decisionType,
            Recommended_Action__c = result.recommendedAction,
            Reasoning__c = result.explanation,
            Confidence__c = (result.confidence * 100)
                .setScale(2, System.RoundingMode.HALF_UP),
            Objective_Mode__c = mode,
            Score__c = result.selected.score,
            Snapshot_Time__c = asOf,
            Approval_Status__c = result.approvalStatus,
            Score_Breakdown__c = JSON.serialize(result.selected.breakdown),
            Rejected_Candidates__c = JSON.serialize(result.rejected)
        );
        if (scenarioId != null) {
            decision.Scenario__c = scenarioId;
            decision.Scenario_Phase__c = phase;
            decision.Step_Index__c = stepIndex;
        }
        insert as user decision;

        Set<String> assetCodes = new Set<String>();
        for (RenewAIDTO.ActionLine line : result.selected.actions) {
            assetCodes.add(line.assetCode);
        }

        Map<String, Id> assetIdByCode = new Map<String, Id>();
        for (RenewAI_Energy_Asset__c asset : [
            SELECT Id, Asset_Code__c
            FROM RenewAI_Energy_Asset__c
            WHERE Asset_Code__c IN :assetCodes
            WITH USER_MODE
        ]) {
            assetIdByCode.put(asset.Asset_Code__c, asset.Id);
        }

        List<Action__c> actions = new List<Action__c>();
        for (RenewAIDTO.ActionLine line : result.selected.actions) {
            actions.add(new Action__c(
                Decision__c = decision.Id,
                Action_Type__c = line.actionType,
                Energy_Asset__c = assetIdByCode.get(line.assetCode),
                Quantity_MW__c = line.quantityMW,
                Scheduled_Start__c = asOf,
                Scheduled_End__c = asOf.addMinutes(
                    RenewAIInputValidator.INTERVAL_MINUTES),
                Status__c = 'Planned'
            ));
        }

        if (!actions.isEmpty()) {
            insert as user actions;
        }

        return decision.Id;
    }

    // ------------------------------------------------------------ response

    private static RenewAIDTO.DecisionResponse toResponse(
        Id decisionId,
        String correlationId,
        Datetime asOf,
        String mode,
        RenewAIDecisionEngine.Context ctx,
        RenewAIDecisionEngine.EngineResult result
    ) {
        RenewAIDTO.DecisionResponse response =
            new RenewAIDTO.DecisionResponse();

        response.correlationId = correlationId;
        response.decisionId = decisionId;
        response.asOf = asOf;
        response.objectiveMode = mode;
        response.confidence = result.confidence;
        response.reserveMW = result.reserveMW;
        response.approvalStatus = result.approvalStatus;
        response.explanation = result.explanation;
        response.selected = result.selected;
        response.alternatives = result.alternatives;
        response.rejected = result.rejected;

        response.inputs = new RenewAIDTO.DecisionInputs();
        response.inputs.renewableMW = ctx.renewableMW;
        response.inputs.demandMW = ctx.demandMW;
        response.inputs.demandGapMW = ctx.demandMW - ctx.renewableMW;
        response.inputs.energyPriceMWh = ctx.priceMWh;

        return response;
    }

    private static RenewAIValidationException validation(
        String field,
        String code,
        String message
    ) {
        return new RenewAIValidationException(
            new List<RenewAIDTO.ErrorDetail>{
                new RenewAIDTO.ErrorDetail(field, code, message)
            }
        );
    }
}
