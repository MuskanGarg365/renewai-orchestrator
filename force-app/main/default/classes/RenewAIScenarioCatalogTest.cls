@IsTest
private class RenewAIScenarioCatalogTest {

    private static final List<String> MODES = new List<String>{
        'Balanced', 'Cost First', 'Clean Energy First', 'Reliability First'
    };

    // Mirrors the seeded 12:00 IST (06:30Z) portfolio: 126.9 MW of the
    // 160.24 MW renewable output is solar.
    private static RenewAIDecisionEngine.Context baseline() {
        RenewAIDecisionEngine.Context ctx =
            new RenewAIDecisionEngine.Context();
        ctx.asOf = Datetime.newInstanceGmt(2026, 10, 9, 6, 30, 0);
        ctx.renewableMW = 160.24;
        ctx.solarMW = 126.9;
        ctx.demandMW = 161.21;
        ctx.priceMWh = 3050;
        ctx.gridLimitMW = 150;
        ctx.confidence = 0.85;
        ctx.gridAssetCode = 'GRID_INDIA_01';
        ctx.batteries.add(new RenewAIDecisionEngine.Battery(
            'BATTERY_MH_01', 20, 80, true));
        ctx.batteries.add(new RenewAIDecisionEngine.Battery(
            'BATTERY_MH_02', 20, 72, true));
        return ctx;
    }

    private static Decimal quantityOf(
        RenewAIDTO.CandidateResult candidate,
        String actionType
    ) {
        Decimal total = 0;
        for (RenewAIDTO.ActionLine line : candidate.actions) {
            if (line.actionType == actionType) {
                total += line.quantityMW;
            }
        }
        return total;
    }

    private static void assertClose(
        Decimal expected, Decimal actual, Decimal tolerance, String message
    ) {
        System.assert(
            actual != null && Math.abs(expected - actual) <= tolerance,
            message + ': expected ' + expected + ' but got ' + actual
        );
    }

    @IsTest
    static void cloudFrontCutsSolarAndConfidence() {
        RenewAIDecisionEngine.Context base = baseline();
        RenewAIScenarioCatalog.Disturbed d = RenewAIScenarioCatalog.apply(
            base, 'Cloud Front', 1);

        assertClose(109.48, d.context.renewableMW, 0.01, 'renewable');
        assertClose(76.14, d.context.solarMW, 0.01, 'solar');
        assertClose(0.55, d.context.confidence, 0.001, 'confidence');
        System.assertEquals(3, d.changes.size());

        // The input context is never modified.
        assertClose(160.24, base.renewableMW, 0.001, 'base renewable');
        assertClose(0.85, base.confidence, 0.001, 'base confidence');
    }

    @IsTest
    static void priceSpikeRaisesThePrice() {
        RenewAIScenarioCatalog.Disturbed d = RenewAIScenarioCatalog.apply(
            baseline(), 'Price Spike', 1);
        assertClose(5490, d.context.priceMWh, 0.01, 'price');
        assertClose(160.24, d.context.renewableMW, 0.001, 'renewable unchanged');
    }

    @IsTest
    static void demandSurgeRaisesDemand() {
        RenewAIScenarioCatalog.Disturbed d = RenewAIScenarioCatalog.apply(
            baseline(), 'Demand Surge', 1);
        assertClose(185.39, d.context.demandMW, 0.02, 'demand');
    }

    @IsTest
    static void batteryOutageTakesTheFirstUnitOffline() {
        RenewAIDecisionEngine.Context base = baseline();
        RenewAIScenarioCatalog.Disturbed d = RenewAIScenarioCatalog.apply(
            base, 'Battery Outage', 1);

        System.assertEquals(false, d.context.batteries[0].available);
        System.assertEquals(true, d.context.batteries[1].available);
        System.assertEquals(true, base.batteries[0].available);
        System.assertEquals(1, d.changes.size());
    }

    @IsTest
    static void intensityScalesTheDisturbance() {
        RenewAIScenarioCatalog.Disturbed half = RenewAIScenarioCatalog.apply(
            baseline(), 'Price Spike', 0.5);
        assertClose(4270, half.context.priceMWh, 0.01, 'half price spike');

        RenewAIScenarioCatalog.Disturbed none = RenewAIScenarioCatalog.apply(
            baseline(), 'Battery Outage', 0);
        System.assertEquals(true, none.context.batteries[0].available);
        System.assertEquals(0, none.changes.size());
    }

    @IsTest
    static void unknownScenarioIsRejected() {
        try {
            RenewAIScenarioCatalog.apply(baseline(), 'Meteor', 1);
            System.assert(false, 'Expected a validation exception');
        } catch (RenewAIValidationException e) {
            System.assertEquals('INVALID_SCENARIO', e.validationErrors[0].code);
        }
    }

    // Regression: every scenario under every objective yields a valid plan.
    @IsTest
    static void everyScenarioGivesAFeasibleBalancedDecision() {
        for (String scenarioType : RenewAIScenarioCatalog.types()) {
            for (String mode : MODES) {
                RenewAIDecisionEngine.Context ctx =
                    RenewAIScenarioCatalog.apply(
                        baseline(), scenarioType, 1).context;
                RenewAIDecisionEngine.EngineResult result =
                    RenewAIDecisionEngine.decide(ctx, mode);
                RenewAIDTO.CandidateResult s = result.selected;
                String label = scenarioType + ' / ' + mode;

                System.assertEquals(true, s.feasible, label);
                System.assertEquals(0, s.rejectionReasons.size(), label);

                Decimal balance = ctx.renewableMW
                    - quantityOf(s, 'Curtail')
                    + quantityOf(s, 'Discharge')
                    + quantityOf(s, 'Buy')
                    - quantityOf(s, 'Charge')
                    - quantityOf(s, 'Sell')
                    - ctx.demandMW;
                System.assert(
                    Math.abs(balance) <= 0.6,
                    label + ' is unbalanced by ' + balance);
            }
        }
    }

    // Regression: expected direction of change for each scenario.
    @IsTest
    static void cloudFrontRaisesReserveAndNeedsApproval() {
        RenewAIDecisionEngine.EngineResult before =
            RenewAIDecisionEngine.decide(baseline(), 'Balanced');
        RenewAIDecisionEngine.EngineResult after =
            RenewAIDecisionEngine.decide(
                RenewAIScenarioCatalog.apply(
                    baseline(), 'Cloud Front', 1).context,
                'Balanced');

        System.assertEquals('Not Required', before.approvalStatus);
        System.assertEquals('Pending', after.approvalStatus);
        System.assert(after.reserveMW > before.reserveMW, 'reserve should rise');
        System.assert(
            quantityOf(after.selected, 'Buy') > quantityOf(before.selected, 'Buy'),
            'more grid purchase after losing solar');
    }

    @IsTest
    static void demandSurgeDischargesMore() {
        RenewAIDecisionEngine.EngineResult before =
            RenewAIDecisionEngine.decide(baseline(), 'Balanced');
        RenewAIDecisionEngine.EngineResult after =
            RenewAIDecisionEngine.decide(
                RenewAIScenarioCatalog.apply(
                    baseline(), 'Demand Surge', 1).context,
                'Balanced');

        System.assert(
            quantityOf(after.selected, 'Discharge') +
                quantityOf(after.selected, 'Buy') >
            quantityOf(before.selected, 'Discharge') +
                quantityOf(before.selected, 'Buy'),
            'more supply is needed after a demand surge');
    }

    @IsTest
    static void batteryOutageLimitsDischargeToTheRemainingUnit() {
        RenewAIDecisionEngine.EngineResult after =
            RenewAIDecisionEngine.decide(
                RenewAIScenarioCatalog.apply(
                    baseline(), 'Battery Outage', 1).context,
                'Cost First');

        // Only one 20 MW unit is left.
        System.assert(
            quantityOf(after.selected, 'Discharge') <= 20.01,
            'discharge exceeds the remaining battery');
        for (RenewAIDTO.ActionLine line : after.selected.actions) {
            System.assertNotEquals('BATTERY_MH_01', line.assetCode,
                'the offline battery must not be dispatched');
        }
    }

    @IsTest
    static void priceSpikeIncreasesTradingValue() {
        RenewAIDecisionEngine.Context spiked = RenewAIScenarioCatalog.apply(
            baseline(), 'Price Spike', 1).context;
        RenewAIDecisionEngine.EngineResult before =
            RenewAIDecisionEngine.decide(baseline(), 'Cost First');
        RenewAIDecisionEngine.EngineResult after =
            RenewAIDecisionEngine.decide(spiked, 'Cost First');

        Decimal sellBefore = quantityOf(before.selected, 'Sell');
        Decimal sellAfter = quantityOf(after.selected, 'Sell');
        System.assert(sellAfter >= sellBefore, 'sales should not fall');
        System.assert(
            sellAfter * spiked.priceMWh > sellBefore * 3050,
            'sales revenue should rise');
    }
}
